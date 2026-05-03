<p align="center">
  <img src="https://raw.githubusercontent.com/jeremy99981/MusicGlass/main/MusicGlass/Assets.xcassets/AppIcon.appiconset/Icon-1024.png" width="128" height="128" alt="MusicGlass Icon" style="border-radius: 24px;">
</p>

<h1 align="center">MusicGlass</h1>

<p align="center">
  <strong>A premium, native iOS music player featuring a stunning "Liquid Glass" interface, powered by YouTube Music discovery.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#installation">Installation</a> •
  <a href="#roadmap">Roadmap</a>
</p>

---

## ✨ Overview

**MusicGlass** is a modern, high-fidelity iOS music player designed with a meticulously crafted SwiftUI interface. It bridges the gap between premium native aesthetics (inspired by Apple Music's "Liquid Glass" materials) and the vast catalog of YouTube Music via a custom, robust InnerTube client. 

Built entirely in **SwiftUI** and powered by **SwiftData** and **AVPlayer**, MusicGlass provides a seamless, fast, and beautiful listening experience without compromising on performance.

> **Disclaimer:** This is a third-party prototype. It is not affiliated with, endorsed by, or associated with YouTube, Google, Apple, or their affiliates. It does not include DRM circumvention.

## 🚀 Key Features

### 🎨 Stunning "Liquid Glass" UI
- Custom material rendering that mimics iOS native blurs perfectly.
- Reactive, smooth micro-animations and transitions.
- A fully responsive player screen, mini-player, and interactive queue.

### 🎧 Uncompromised Playback
- **Native `AVPlayer` Engine**: Enjoy high-quality audio streams directly.
- **System Integration**: Full support for Background Audio, Lock Screen metadata, and Control Center commands.
- **Smart Queue Management**: Features shuffle, repeat modes, and seamless track transitions.

### 🔍 Discovery & Library (InnerTube)
- **Home Feed**: Personalized feed leveraging YouTube Music (`FEmusic_home`), blended with local history.
- **Lightning Fast Search**: 350ms debounced search with grouped results (Songs, Albums, Artists, Playlists, Videos).
- **Offline First Metadata**: Local persistence of your Favorites and History using **SwiftData**.

### 🎤 Immersive Lyrics
- Built-in integration with **LRCLib** for real-time plain and synced lyrics lookup.

---

## 🛠️ Technological Advancements

MusicGlass isn't just another music wrapper. It’s built on a modern, robust architecture:

- **SwiftUI 100%**: Completely built using the latest declarative UI paradigms.
- **SwiftData**: Modern, fast local database for user persistence.
- **Custom Networking Logger**: Redaction-aware network logger to securely monitor API calls without leaking sensitive tokens.
- **Defensive JSON Mapping**: Highly permissive InnerTube client to gracefully handle YouTube Music API payload changes.
- **Decoupled Architecture**: Clean separation between `App`, `Core`, `Networking`, `YouTubeMusic`, `Playback`, `Persistence`, and `UI` layers.

## 📦 Installation & Setup

1. Clone the repository and open `MusicGlass.xcodeproj` in **Xcode 26.4** or newer.
2. Select the `MusicGlass` scheme.
3. Build and run on an **iOS 26+** device or simulator for the full Liquid Glass experience. *(iOS 17/18 provides a material fallback)*.

### CLI Build Check

```bash
xcodebuild -project MusicGlass.xcodeproj -target MusicGlass -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MusicGlass.xcodeproj -target MusicGlassTests -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

*Note: The app requires network access for discovery and playback. Background audio is enabled via `UIBackgroundModes`.*

## 🛣️ Roadmap

- [ ] **Authentication**: Secure YouTube Music login via Keychain.
- [ ] **Library Sync**: Remote synchronization for songs, albums, artists, and playlists.
- [ ] **Advanced Lyrics**: Karaoke-style synced lyrics highlighting.
- [ ] **Intelligent Offline Mode**: Caching for offline playback.
- [ ] **Ecosystem**: Widgets, Live Activities, and potential CarPlay/ShazamKit integration.
- [ ] **Social**: Last.fm scrobbling and listen-together sessions.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/jeremy99981/MusicGlass/issues).

---

<p align="center">
  <i>Crafted with ❤️ for music lovers and Swift developers.</i>
</p>
