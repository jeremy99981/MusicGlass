# MusicGlass

MusicGlass is a lightweight, installable music player. The Next.js frontend can
run independently and connect at runtime to the Go backend hosted on a Mac or
another computer. The backend owns catalog access, audio streaming, accounts,
libraries and synchronized WebSocket sessions.

## Start on the Mac

Requirements: Docker Desktop, OrbStack, or Colima with Docker Compose.

```sh
cp .env.example .env
docker compose up -d --build
```

Open `http://localhost:8090`. From another device on the same Wi-Fi, use the
Mac's LAN address, for example `http://192.168.1.12:8090`.

The local Next.js development server also targets this Docker backend by
default. Start Docker first, then run `npx pnpm@10.12.1 dev`; requests to
`http://localhost:3000/api/*` are proxied to `http://127.0.0.1:8090/api/*`.

Check the stack and API:

```sh
docker compose ps
curl http://localhost:8090/api/v2/health
```

## Remote access

### Temporary test URL

This mode needs no account. The URL changes after a container restart and is
for testing only.

```sh
docker compose --profile test-remote up -d --build
docker compose logs -f tunnel-test
```

Copy the displayed `https://...trycloudflare.com` URL into **Settings > Remote
connection** in the web player. The setting controls the catalog, audio, auth
and WebSocket connections without rebuilding or redeploying Next.js.

### Stable URL

1. Create a remotely-managed Cloudflare Tunnel.
2. Add a public hostname targeting `http://proxy:80`.
3. Put its token in `.env` as `CLOUDFLARE_TUNNEL_TOKEN`.
4. Add the frontend URL to `CORS_ALLOWED_ORIGINS`.
5. Start the stable profile:

```sh
docker compose --profile remote up -d --build
```

The tunnel is outbound-only; no router port forwarding is required. Treat its
token as a secret because it can start a connector for that tunnel.

## Move to another computer

Copy this directory without `.env`, then create a new `.env` from
`.env.example`. Docker creates PostgreSQL and Redis volumes automatically. To
move existing user data too, export and restore the `postgres_data` volume.

## Web development and tests

```sh
npx pnpm@10.12.1 install
npx pnpm@10.12.1 dev
npx pnpm@10.12.1 lint
npx pnpm@10.12.1 typecheck
npx pnpm@10.12.1 test:unit
npx pnpm@10.12.1 test:e2e
```

The public Docker entrypoint is Nginx on port `8090`. It proxies `/api`, audio
Range requests and WebSocket upgrades to Go while Next.js serves the UI.

## YouTube Music resolution

The Go backend uses the same useful InnerTube strategy as the Metrolist-style
Flutter client: anonymous visitor bootstrap, `ANDROID_VR`/Android/iOS/TV player
fallbacks, `/next` recommendations and a generic YouTube resolver as the final
fallback. Optional `YOUTUBE_COOKIE_HEADER`, `YOUTUBE_AUTH_HEADER` and
`YOUTUBE_VISITOR_DATA` values improve access to account-bound or restricted
content, but public playback is attempted without credentials first.
