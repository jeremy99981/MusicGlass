# MusicGlass

MusicGlass is a native SwiftUI iOS MVP for a premium music player UI backed by YouTube Music discovery and stream metadata through a contained InnerTube client.

It is a third-party prototype and is not affiliated with, endorsed by, sponsored by, or associated with YouTube, Google, Apple, or their affiliates. It does not include DRM circumvention, embedded credentials, or copied Metrolist GPL code.

## Architecture

- `App`: app entry point, dependency container, navigation root, global player sheets.
- `Core`: domain models, errors, logging, formatting helpers.
- `Networking`: `URLSession` HTTP client, request primitives, redaction-aware network logger.
- `YouTubeMusic`: permissive InnerTube client, DTOs, defensive JSON mapper, lyrics service.
- `Playback`: `AVPlayer`, audio session, queue, Now Playing, Control Center commands, cache cleanup.
- `Persistence`: SwiftData records and repositories for favorites, history, playlists, cache metadata.
- `UI`: reusable design system, Liquid Glass fallback materials, artwork/cards/rows/state views.
- `Features`: Home, Search, Library, Player, Lyrics, Settings screens and view models.
- `MusicGlassTests`: parser and queue unit tests with local fixtures.

## Run

1. Open `MusicGlass.xcodeproj` in Xcode 26.4 or newer.
2. Select the `MusicGlass` scheme.
3. Run on an iOS 26 simulator/device for native Liquid Glass, or iOS 17/18 for the material fallback.

CLI build check:

```sh
xcodebuild -project MusicGlass.xcodeproj -target MusicGlass -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MusicGlass.xcodeproj -target MusicGlassTests -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

The app requires network access to search and resolve playable YouTube Music streams. Background audio is enabled through `UIBackgroundModes = audio`.

## MVP Scope

Implemented:

- Onboarding disclaimer.
- Home feed from YouTube Music `FEmusic_home`, with local recent history inserted.
- Search with 350 ms debounce, suggestions, grouped songs/albums/artists/playlists/videos.
- Native AVPlayer playback from compatible InnerTube audio URLs.
- Mini-player, full-player, queue, shuffle, repeat, seek.
- Background audio, lock screen metadata, Control Center commands.
- Local favorites and history through SwiftData.
- LRCLib plain/synced lyrics lookup architecture.
- Settings for cache, theme placeholder, audio quality placeholder, debug toggle placeholder.
- Defensive parser tests and queue tests.

## Limits

- No YouTube Music login yet.
- No remote library sync.
- No offline audio download in this MVP; metadata/artwork cache cleanup only.
- No JS signature deciphering or DRM circumvention.
- YouTube Music response shapes may change; parsers are intentionally permissive and isolated.
- Album/artist/playlist detail parsing is basic and depends on exposed InnerTube renderers.
- Audio quality picker is a UI placeholder until format selection policy is expanded.

## Roadmap

- Secure YouTube Music login through an isolated auth service and Keychain storage.
- Account library sync for songs, albums, artists, and playlists.
- Remote playlist management and playlist import.
- More robust album/artist/playlist parsers with JSON fixtures.
- Synced lyrics highlighting in the player.
- Legal/terms-aware intelligent offline mode.
- Last.fm scrobbling.
- AirPlay refinements.
- CarPlay exploration if legally and technically appropriate.
- Widgets and optional Live Activity.
- ShazamKit recognition.
- Listen together / shared queue experiments.
