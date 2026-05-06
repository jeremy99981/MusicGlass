<p align="center">
  <img src="MusicGlass/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png" width="128" height="128" alt="MusicGlass Icon" style="border-radius: 24px;">
</p>

<h1 align="center">MusicGlass</h1>

<p align="center">
  <strong>🇬🇧 English</strong> | <a href="README.fr.md">🇫🇷 Français</a>
</p>

<p align="center">
  <strong>A premium, native iOS and Android music player featuring a stunning "Liquid Glass" interface, powered by YouTube Music discovery.</strong>
</p>

<p align="center">
  <a href="#-overview">Overview</a> •
  <a href="#-key-features">Features</a> •
  <a href="#%EF%B8%8F-architecture-deep-dive">Architecture</a> •
  <a href="#-installation--setup">Installation</a> •
  <a href="#%EF%B8%8F-roadmap">Roadmap</a>
</p>

---

## ✨ Overview

**MusicGlass** is a modern, high-fidelity music player available on both **iOS** and **Android**, designed with a meticulously crafted interface. It bridges the gap between premium native aesthetics (inspired by Apple Music's "Liquid Glass" materials and Material Design 3) and the vast catalog of YouTube Music via a custom, robust InnerTube client. 

Built entirely in **SwiftUI** for iOS and **Jetpack Compose** for Android, MusicGlass provides a seamless, fast, and beautiful cross-platform listening experience without compromising on performance.

> **Disclaimer:** This is a third-party prototype. It is not affiliated with, endorsed by, or associated with YouTube, Google, Apple, or their affiliates. It does not include DRM circumvention.

---

## 🚀 Key Features

### 🎨 Stunning "Liquid Glass" UI & UX
- **Custom Material Rendering:** Implements bespoke blur and vibrancy effects that perfectly mimic iOS native blurs, bringing the app to life.
- **Fluid Micro-Animations:** Reactive UI with state-driven animations for every interaction, from pressing play to expanding the player.
- **Dynamic Layouts:** A fully responsive Full-Player screen, an elegant Mini-Player, and a drag-and-drop interactive Queue.

### 🎧 Uncompromised Playback Engine
- **Native `AVPlayer` Core:** Leverages Apple's robust audio framework for reliable, high-quality audio streaming.
- **Deep System Integration:** Full background audio support, Lock Screen metadata sync, and native Control Center commands (`MPRemoteCommandCenter`).
- **Smart Queue Management:** Advanced queueing system supporting shuffle, loop modes, dynamic track insertion, and gapless-like transitions.

### 🔍 Discovery & Library (InnerTube API)
- **Personalized Home Feed:** A dynamic feed leveraging YouTube Music's `FEmusic_home` endpoint, intelligently blended with your local listening history.
- **Lightning Fast Search:** 350ms debounced auto-complete search delivering grouped results (Songs, Albums, Artists, Playlists, Videos) instantly.
- **Offline-First Metadata:** Caches your Favorites, History, and Library data locally using **SwiftData** for instant load times.

### 🎤 Immersive Lyrics Integration
- **LRCLib Ecosystem:** Built-in integration with the open-source LRCLib.
- **Real-time Sync:** Supports both plain text and time-synced lyrics with line-by-line highlighting in the player.

---

## 🛠️ Architecture Deep Dive

MusicGlass is engineered with scalability, maintainability, and modern iOS development patterns in mind. It utilizes a highly decoupled, modular architecture:

### 1. `App` & `UI` Layer
- **Entry Point:** The application root relies on a clean Dependency Injection container.
- **Navigation:** State-driven navigation handling global player sheets overlaying the main tab view.
- **Design System:** Reusable UI components (Artwork Cards, Rows, State Views) and "Liquid Glass" fallback materials ensuring backward compatibility with iOS 17.

### 2. `Features` (MVVM)
Every core feature (Home, Search, Library, Player, Lyrics, Settings) is separated into its own module containing SwiftUI Screens and heavily tested ViewModels.

### 3. `Playback` Engine
An isolated layer wrapping `AVPlayer` and `AVAudioSession`.
- Handles `NowPlayingInfoCenter` updates.
- Manages the `PlayerQueue` logic (upcoming tracks, history stack).
- Takes care of cache cleanup and resource lifecycle.

### 4. `YouTubeMusic` (InnerTube Client)
A bespoke, highly permissive networking client interfacing with YouTube's internal APIs.
- **Defensive JSON Mapping:** Uses custom parsers and DTOs designed to gracefully handle unannounced API payload changes.
- **Lyrics Service:** Fetches and synchronizes external metadata without interrupting playback.

### 5. `Networking` & `Core`
- **HTTPClient:** A lightweight `URLSession` wrapper providing async/await request primitives.
- **Redaction-Aware Logger:** A custom logging system that ensures sensitive tokens (SAPISID, Authorization headers) are never leaked in the console.

### 6. `Persistence`
Powered entirely by **SwiftData**.
- Repositories for managing local records (Favorites, History, Custom Playlists).
- Handles metadata caching to reduce unnecessary network roundtrips.

---

## 📦 Installation & Setup

### 🍎 iOS
1. Clone the repository and open `MusicGlass.xcodeproj` in **Xcode 26.4** or newer.
2. Select the `MusicGlass` scheme.
3. Build and run on an **iOS 26+** device or simulator for the full Liquid Glass experience. *(iOS 17/18 provides a material fallback)*.

### 🤖 Android
1. Open the `MusicGlassAndroid` directory in **Android Studio**.
2. Let Gradle sync the project dependencies.
3. Build and run the `app` configuration on an emulator or physical device running Android 8.0 (API 26) or higher.

### CLI Build Check

```bash
xcodebuild -project MusicGlass.xcodeproj -target MusicGlass -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MusicGlass.xcodeproj -target MusicGlassTests -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

*Note: The app requires network access for discovery and playback. Background audio is enabled via `UIBackgroundModes`.*

---

## 🛣️ Roadmap

- [ ] **Authentication:** Secure YouTube Music login via Keychain.
- [ ] **Library Sync:** Remote synchronization for songs, albums, artists, and playlists.
- [ ] **Advanced Lyrics:** Karaoke-style synced lyrics highlighting and translation overlay.
- [ ] **Intelligent Offline Mode:** Audio file caching for true offline playback.
- [ ] **Ecosystem Integration:** iOS Widgets, Live Activities, and potential CarPlay/ShazamKit integration.
- [ ] **Social Features:** Last.fm scrobbling and listen-together SharePlay sessions.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! 
If you find a bug or have a suggestion, feel free to check the [issues page](https://github.com/jeremy99981/MusicGlass/issues).

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

<p align="center">
  <i>Crafted with ❤️ for music lovers and Swift developers.</i>
</p>
