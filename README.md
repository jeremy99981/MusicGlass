# MusicGlass

MusicGlass is split into two deployable parts:

- `MusicGlassPWA/`: the responsive Next.js PWA and its bundled API service.
- `Backend/music-main/`: the backend stack intended to run locally on a Mac with Docker.

## Run the Mac backend

```sh
cd Backend/music-main
cp .env.example .env
docker compose up -d --build
```

## Run the PWA

See [`MusicGlassPWA/README.md`](MusicGlassPWA/README.md) for local development,
remote Cloudflare access, configuration and validation commands.

The Flutter and legacy native iOS workspaces are intentionally not part of this
repository distribution.
