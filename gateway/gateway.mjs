// Searxly gateway — a small proxy that holds the secret keys (io.net, 0x) server-side so the app
// never ships them. Each route allowlists its upstream paths so a leaked APP_TOKEN can't be turned
// into a general-purpose proxy. Env: IONET_KEY, ZEROX_KEY, APP_TOKEN, RATE_LIMIT, PORT. Node 18+.

import http from 'node:http';
import { Readable } from 'node:stream';

const IONET_KEY = process.env.IONET_KEY;
const ZEROX_KEY = process.env.ZEROX_KEY || '';
const APP_TOKEN = process.env.APP_TOKEN || '';
const PORT      = Number(process.env.PORT || 8787);

const IONET_UPSTREAM = 'https://api.intelligence.io.solutions/api/v1/chat/completions';
const ZEROX_UPSTREAM = 'https://api.0x.org';

// Free, keyless, Etherscan-compatible explorers per chain (chainid → host).
const BLOCKSCOUT_HOSTS = {
  '8453':  'https://base.blockscout.com',     // Base
  '1':     'https://eth.blockscout.com',      // Ethereum
  '10':    'https://explorer.optimism.io',    // Optimism
  '42161': 'https://arbitrum.blockscout.com', // Arbitrum One
  '137':   'https://polygon.blockscout.com',  // Polygon
};

const MAX_BODY  = 256 * 1024;
const LIMIT     = Number(process.env.RATE_LIMIT || 120);
const WINDOW_MS = 60 * 60 * 1000;

const hits = new Map();
function rateLimited(ip) {
  const now = Date.now();
  const rec = hits.get(ip);
  if (!rec || now > rec.reset) { hits.set(ip, { count: 1, reset: now + WINDOW_MS }); return false; }
  rec.count++;
  return rec.count > LIMIT;
}

function clientIP(req) {
  return String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '')
    .split(',')[0].trim();
}

function sendJSON(res, status, obj) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(obj));
}

function pipeThrough(res, upstream) {
  res.writeHead(upstream.status, {
    'content-type': upstream.headers.get('content-type') || 'application/json',
    'cache-control': 'no-cache'
  });
  if (upstream.body) Readable.fromWeb(upstream.body).pipe(res);
  else res.end();
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204).end(); return; }

  if (req.method === 'GET' && req.url === '/health') {
    return sendJSON(res, 200, { ok: true });
  }

  if (APP_TOKEN) {
    const auth = req.headers['authorization'] || '';
    if (auth !== `Bearer ${APP_TOKEN}`) {
      return sendJSON(res, 401, { error: { message: 'unauthorized' } });
    }
  }

  if (rateLimited(clientIP(req))) {
    return sendJSON(res, 429, { error: { message: 'Too many requests. Please wait and try again.' } });
  }

  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;

  if (req.method === 'POST' && path.startsWith('/v1/chat/completions')) {
    return handleAI(req, res);
  }
  if (req.method === 'GET' && path.startsWith('/wallet/0x/')) {
    return handleZeroEx(res, url, path);
  }
  if (req.method === 'GET' && path === '/wallet/etherscan') {
    return handleEtherscan(res, url);
  }

  return sendJSON(res, 404, { error: { message: 'not found' } });
});

async function handleAI(req, res) {
  if (!IONET_KEY) {
    return sendJSON(res, 500, { error: { message: 'Searxly AI is not configured.' } });
  }

  let size = 0;
  const chunks = [];
  try {
    for await (const c of req) {
      size += c.length;
      if (size > MAX_BODY) { res.writeHead(413).end(); return; }
      chunks.push(c);
    }
  } catch {
    return sendJSON(res, 400, { error: { message: 'bad request' } });
  }
  const body = Buffer.concat(chunks).toString('utf8');

  try {
    const upstream = await fetch(IONET_UPSTREAM, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'authorization': `Bearer ${IONET_KEY}` },
      body
    });
    pipeThrough(res, upstream);
  } catch {
    return sendJSON(res, 502, { error: { message: 'Searxly AI is temporarily unavailable.' } });
  }
}

async function handleZeroEx(res, url, path) {
  if (!ZEROX_KEY) {
    return sendJSON(res, 500, { error: { message: 'Swaps are not configured.' } });
  }
  const rest = path.slice('/wallet/0x/'.length);
  if (!rest.startsWith('swap/')) {   // allowlist: swap endpoints only
    return sendJSON(res, 403, { error: { message: 'forbidden path' } });
  }
  const upstreamURL = `${ZEROX_UPSTREAM}/${rest}${url.search}`;
  try {
    const upstream = await fetch(upstreamURL, {
      method: 'GET',
      headers: { '0x-api-key': ZEROX_KEY, '0x-version': 'v2', 'accept': 'application/json' }
    });
    pipeThrough(res, upstream);
  } catch {
    return sendJSON(res, 502, { error: { message: 'Swap service temporarily unavailable.' } });
  }
}

async function handleEtherscan(res, url) {
  const params = url.searchParams;
  const moduleName = params.get('module') || '';
  if (moduleName !== 'account' && moduleName !== 'logs') {   // allowlist: history + approvals only
    return sendJSON(res, 403, { error: { message: 'forbidden module' } });
  }
  const host = BLOCKSCOUT_HOSTS[params.get('chainid') || '8453'];
  if (!host) {
    return sendJSON(res, 200, { status: '0', message: 'Chain not supported', result: [] });
  }
  params.delete('apikey');
  const upstreamURL = `${host}/api?${params.toString()}`;
  try {
    const upstream = await fetch(upstreamURL, {
      method: 'GET', headers: { 'accept': 'application/json' }, redirect: 'follow'
    });
    pipeThrough(res, upstream);
  } catch {
    return sendJSON(res, 502, { error: { message: 'History service temporarily unavailable.' } });
  }
}

server.listen(PORT, '127.0.0.1', () => console.log(`Searxly gateway listening on 127.0.0.1:${PORT}`));
