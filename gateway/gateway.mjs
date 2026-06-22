// Searxly gateway
//
// A tiny, dependency-free proxy that sits between the Searxly app and the third-party services it
// needs a secret key for. The app talks to THIS server; this server is the ONLY place those keys
// live. Nothing secret ever ships inside the app.
//
// Routes (all require Authorization: Bearer <APP_TOKEN>):
//   POST /v1/chat/completions   → io.net (Searxly AI). OpenAI-compatible; streamed back unchanged.
//   GET  /wallet/0x/swap/...     → api.0x.org   (token swap quotes). Injects the 0x key.
//   GET  /wallet/etherscan?...   → Blockscout   (wallet history / token discovery), keyless & free.
//                                  Picks the chain's Blockscout host from the `chainid` query param,
//                                  so no paid explorer API key is ever needed.
//   GET  /health                 → liveness probe (no auth).
//
// The wallet routes are deliberately NOT open proxies: each one allowlists the upstream paths/modules
// the app actually uses, so a leaked APP_TOKEN can't turn our keys into a free general-purpose proxy.
//
// Env vars (set in the systemd unit, NOT in code):
//   IONET_KEY     - rotated io.net key (required for /v1/chat/completions). Never ships in the app.
//   ZEROX_KEY     - 0x API key (required for /wallet/0x). https://dashboard.0x.org
//                   (/wallet/etherscan needs no key — it uses Blockscout, which is free + keyless.)
//   APP_TOKEN     - a long random string the app must send as "Authorization: Bearer <APP_TOKEN>".
//                   Soft gate against casual abuse + lets you rotate without rebuilding the app.
//   RATE_LIMIT    - max requests per IP per hour across all routes (default 120).
//   PORT          - local port to listen on (default 8787). Keep it behind Caddy/HTTPS; do not expose.
//
// Requires Node 18+ (uses global fetch + Readable.fromWeb).

import http from 'node:http';
import { Readable } from 'node:stream';

const IONET_KEY = process.env.IONET_KEY;
const ZEROX_KEY = process.env.ZEROX_KEY || '';
const APP_TOKEN = process.env.APP_TOKEN || '';
const PORT      = Number(process.env.PORT || 8787);

const IONET_UPSTREAM = 'https://api.intelligence.io.solutions/api/v1/chat/completions';
const ZEROX_UPSTREAM = 'https://api.0x.org';

// Free, keyless, Etherscan-compatible explorers per chain (chainid → host). Used by /wallet/etherscan
// so wallet history / token discovery need no paid API key. Add chains here as the wallet gains them.
const BLOCKSCOUT_HOSTS = {
  '8453':  'https://base.blockscout.com',     // Base
  '1':     'https://eth.blockscout.com',      // Ethereum
  '10':    'https://explorer.optimism.io',    // Optimism
  '42161': 'https://arbitrum.blockscout.com', // Arbitrum One
  '137':   'https://polygon.blockscout.com',  // Polygon
};

const MAX_BODY  = 256 * 1024;                          // 256 KB request cap (AI route)
const LIMIT     = Number(process.env.RATE_LIMIT || 120); // requests per window, per IP, across routes
const WINDOW_MS = 60 * 60 * 1000;                     // 1 hour

// Very small in-memory per-IP rate limit. (Per-user free-prompt limits come later via the wallet.)
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

// Stream an upstream fetch() Response straight back to the client, unchanged.
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

  // Shared soft gate for every real route.
  if (APP_TOKEN) {
    const auth = req.headers['authorization'] || '';
    if (auth !== `Bearer ${APP_TOKEN}`) {
      return sendJSON(res, 401, { error: { message: 'unauthorized' } });
    }
  }

  // Shared per-IP rate limit.
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

// MARK: - Searxly AI (io.net), OpenAI-compatible, streamed.
async function handleAI(req, res) {
  if (!IONET_KEY) {
    return sendJSON(res, 500, { error: { message: 'Searxly AI is not configured.' } });
  }

  // Read the request body (capped).
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

// MARK: - 0x Swap API. /wallet/0x/<rest> → https://api.0x.org/<rest>, with our key attached.
async function handleZeroEx(res, url, path) {
  if (!ZEROX_KEY) {
    return sendJSON(res, 500, { error: { message: 'Swaps are not configured.' } });
  }
  const rest = path.slice('/wallet/0x/'.length);
  // Allowlist: only the swap endpoints the app uses — never an open proxy to api.0x.org on our key.
  if (!rest.startsWith('swap/')) {
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

// MARK: - Wallet history. /wallet/etherscan?... → the chain's free Blockscout (Etherscan-compatible).
async function handleEtherscan(res, url) {
  const params = url.searchParams;
  // Allowlist the modules the app uses (history/token discovery = account, approvals = logs).
  const moduleName = params.get('module') || '';
  if (moduleName !== 'account' && moduleName !== 'logs') {
    return sendJSON(res, 403, { error: { message: 'forbidden module' } });
  }
  // The app's `chainid` selects which chain's explorer to hit. Unknown chains degrade to an
  // empty-but-valid Etherscan-style result so the app just shows no history (rather than an error).
  const host = BLOCKSCOUT_HOSTS[params.get('chainid') || '8453'];
  if (!host) {
    return sendJSON(res, 200, { status: '0', message: 'Chain not supported', result: [] });
  }
  params.delete('apikey');   // Blockscout is keyless — drop any stray key param
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
