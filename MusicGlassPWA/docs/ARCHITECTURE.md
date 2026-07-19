# Architecture

## Compatibility boundary

The copied Go service keeps every legacy v1 route for Flutter. Browser-specific endpoints live under `/api/v2` and use same-origin cookies. Breaking changes must be introduced only in v2.

## Media boundary

The browser never receives provider credentials and never calls privileged YouTube Music endpoints directly. Go resolves catalog metadata and short-lived playback sources, then proxies Range-capable audio through `/api/v2/media/stream/:id`.

## Runtime

- Next.js owns rendering, PWA installation and responsive interaction.
- A singleton `HTMLAudioElement` survives client-side route changes.
- Go owns identities, library data, provider access and shared-session authority.
- PostgreSQL stores durable data.
- Redis is reserved for session presence, snapshots and Pub/Sub in the next migration milestone.
- Nginx provides a same-origin boundary for cookies, APIs, WebSockets and Range streaming.
- The browser may override the backend origin at runtime. REST, media and WebSocket URLs are derived from that single setting.
- Cloudflare Tunnel provides optional outbound-only remote access. A named tunnel is the stable mode; TryCloudflare is test-only.
