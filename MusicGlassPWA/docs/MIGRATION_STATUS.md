# Migration status

## Complete

- Legacy Flutter and Go source archive with SHA-256 verification.
- Separate protected secret copy.
- Independent Next.js/TypeScript workspace.
- Responsive MusicGlass shell for mobile and desktop.
- Persistent global player state and Media Session integration.
- Local audio preview with HTTP Range, seek and queue controls.
- Installable manifest and conservative offline service worker.
- Legacy Go API copied without route removals.
- Initial cookie/CSRF-based API v2 endpoints.
- Cookie-authenticated API v2 session creation and WebSocket handshake.
- PostgreSQL, Redis, Nginx and Docker topology.
- Shared Zod contracts and generated-client boundary.

## Gated

- Provider-backed catalog and streaming: requires provider credentials and legal/contractual approval.
- Redis-backed multi-instance session replication: single-instance WebSocket v2 is operational; Redis persistence and Pub/Sub remain.
- Full account/library screens: API compatibility layer exists, UI integration follows the staged migration.
