# Searxly gateway

A tiny proxy between the Searxly app and the third-party services it needs to reach: io.net
(Searxly AI), 0x (token swaps), and Blockscout (wallet history / token discovery). The app talks to
this server; this server is the only place the keyed services' secrets live, so none of them ship
inside the app. It also rate-limits and can enforce free-prompt limits later.

Routes (all require `Authorization: Bearer <APP_TOKEN>`):
- `POST /v1/chat/completions` → io.net (OpenAI-compatible, streamed). Needs `IONET_KEY`.
- `GET  /wallet/0x/swap/...` → api.0x.org (allowlisted to `swap/…`). Needs `ZEROX_KEY`.
- `GET  /wallet/etherscan?...` → Blockscout, per-chain by `chainid` (allowlisted to `module=account|logs`).
  **No key needed** — Blockscout is free + keyless. (Etherscan was dropped: its free tier doesn't cover Base.)

Deploy on your BitLaunch VPS (Ubuntu assumed). All commands run on the server over SSH.

## 0. Point a subdomain at the server
In your DNS (wherever `searxly.app` is managed), add an **A record**:

    gateway   →   <your BitLaunch server IPv4>

Wait a few minutes for it to resolve. (The apex `searxly.app` can stay on Vercel — a subdomain is independent.)

## 1. Install Node 20
```
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

## 2. Install the gateway
```
sudo mkdir -p /opt/searxly-gateway
sudo cp gateway.mjs /opt/searxly-gateway/
```
(or paste `gateway.mjs` into that path with `sudo nano /opt/searxly-gateway/gateway.mjs`)

## 3. Configure + run as a service
Edit `searxly-gateway.service`:
- `IONET_KEY` = your **rotated** io.net key (revoke the old one first at ai.io.net — it's burned).
- `ZEROX_KEY` = your 0x API key (free at https://dashboard.0x.org).
- `APP_TOKEN` = a random string: `openssl rand -hex 32`

(Wallet history needs no key — `/wallet/etherscan` uses Blockscout. A route whose key is left blank
just returns a 500 for that feature — e.g. omit `ZEROX_KEY` and AI still works, swaps say "not
configured". The app falls back to a user-supplied key if one is set.)

Then:
```
sudo cp searxly-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now searxly-gateway
sudo systemctl status searxly-gateway      # should say "active (running)"
```

## 4. HTTPS with Caddy (automatic certificate)
```
sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt-get update && sudo apt-get install -y caddy
```
Put your subdomain in `/etc/caddy/Caddyfile` (see the provided `Caddyfile`), then:
```
sudo systemctl reload caddy
```

## 5. Firewall (only 80/443 + SSH; never expose 8787)
```
sudo ufw allow OpenSSH
sudo ufw allow 80,443/tcp
sudo ufw enable
```

## 6. Test
```
curl https://gateway.searxly.app/health
# -> {"ok":true}

curl https://gateway.searxly.app/v1/chat/completions \
  -H "authorization: Bearer <your APP_TOKEN>" \
  -H "content-type: application/json" \
  -d '{"model":"meta-llama/Llama-3.3-70B-Instruct","messages":[{"role":"user","content":"say hi"}]}'

# 0x swap quote (key injected server-side):
curl "https://gateway.searxly.app/wallet/0x/swap/allowance-holder/price?chainId=8453&sellToken=0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee&buyToken=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913&sellAmount=1000000000000000" \
  -H "authorization: Bearer <your APP_TOKEN>"

# Etherscan history (key injected server-side):
curl "https://gateway.searxly.app/wallet/etherscan?chainid=8453&module=account&action=txlist&address=0x0000000000000000000000000000000000000000&sort=desc&page=1&offset=5" \
  -H "authorization: Bearer <your APP_TOKEN>"
```

## 7. Point the app at it
One place — `Searxly/Services/SearxlyGateway.swift` — holds the host + app token for **every** route
(AI, swaps, history):
```swift
static let host     = "https://gateway.searxly.app"
static let appToken = "<your APP_TOKEN>"   // soft gate; the REAL upstream keys now live only on the server
```
Rebuild. The app no longer carries the io.net, 0x, or Etherscan keys. The wallet automatically routes
swaps and history through the gateway unless the user has entered their own key in Settings → Wallet
(that path still talks to the upstream directly).

## Notes / limits
- `APP_TOKEN` still ships inside the app, so it's a *soft* gate (stops casual abuse, rotatable server-side).
  Real per-user limits = wire the in-app wallet sign-in (SIWE) to a per-user token check here later.
- The wallet routes are **not** open proxies: `/wallet/0x` only allows `swap/…` paths and `/wallet/etherscan`
  only `module=account|logs`, so a leaked `APP_TOKEN` can't run arbitrary queries on your keys.
- The per-IP rate limit is in-memory and shared across routes (resets on restart). Default 120/hr per IP,
  tune with `RATE_LIMIT`. Move to Redis if you scale.
- Billing/legal ownership of the server + keys should sit with a trusted adult before public launch.
