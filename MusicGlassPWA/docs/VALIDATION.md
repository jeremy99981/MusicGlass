# Validation report

Validated on 2026-06-15.

## Legacy protection

- Source archive checksum verification: passed.
- PostgreSQL custom dump: created.
- Restore into an isolated database: passed.
- Exact source/restored row counts: matched.
- Original Flutter and Go directories: not moved or rewritten.

## Web

- TypeScript strict check: passed.
- ESLint: passed without warnings.
- Vitest playback tests: 3 passed.
- Next.js production build: passed.
- Shared first-load JavaScript: approximately 102 kB.
- Routes validated: `/`, `/search`, `/library`, `/settings`, `/login`, `/offline`.
- Manifest and service worker: served successfully.
- Local preview audio Range request: `206 Partial Content`.

## API

- Go tests: passed in Go 1.25 Docker image.
- Docker Compose configuration and build: passed.
- API v1 signup through Nginx: passed.
- API v2 signup/login/me: passed.
- HttpOnly access and refresh cookies: issued.
- Mutation without CSRF: rejected with 403.
- Mutation with CSRF: accepted.
- Session create and lookup: passed.
- Cookie-authenticated WebSocket upgrade: `101 Switching Protocols`.
- Initial participant snapshot: received.

## Running stack

The PWA is exposed at `http://localhost:8090` through Nginx. The original Flutter backend stack remains separate.

Provider-backed catalog and production streaming remain disabled until an approved provider adapter and credentials are configured.
