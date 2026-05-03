<p align="center">
  <img src="MusicGlass/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png" width="128" height="128" alt="Icône MusicGlass" style="border-radius: 24px;">
</p>

<h1 align="center">MusicGlass</h1>

<p align="center">
  <a href="README.md">🇬🇧 English</a> | <strong>🇫🇷 Français</strong>
</p>

<p align="center">
  <strong>Un lecteur de musique iOS natif haut de gamme, doté d'une superbe interface "Liquid Glass" et propulsé par la découverte de YouTube Music.</strong>
</p>

<p align="center">
  <a href="#-aper%C3%A7u">Aperçu</a> •
  <a href="#-fonctionnalit%C3%A9s-cl%C3%A9s">Fonctionnalités</a> •
  <a href="#%EF%B8%8F-plong%C3%A9e-dans-larchitecture">Architecture</a> •
  <a href="#-installation--configuration">Installation</a> •
  <a href="#%EF%B8%8F-roadmap-feuille-de-route">Roadmap</a>
</p>

---

## ✨ Aperçu

**MusicGlass** est un lecteur de musique iOS moderne et haute-fidélité, conçu avec une interface SwiftUI méticuleusement soignée. Il fait le pont entre une esthétique native premium (inspirée des matériaux "Liquid Glass" d'Apple Music) et le vaste catalogue de YouTube Music via un client InnerTube personnalisé et robuste.

Entièrement développé en **SwiftUI** et propulsé par **SwiftData** et **AVPlayer**, MusicGlass offre une expérience d'écoute fluide, rapide et magnifique sans faire de compromis sur les performances.

> **Avertissement :** Ceci est un prototype tiers. Il n'est ni affilié, ni approuvé, ni associé à YouTube, Google, Apple ou leurs affiliés. Il n'inclut aucun contournement de DRM.

---

## 🚀 Fonctionnalités clés

### 🎨 Superbe Interface "Liquid Glass" (UI/UX)
- **Rendu Matériel Sur-Mesure :** Implémente des effets de flou et de vibrance sur-mesure qui reproduisent parfaitement les flous natifs d'iOS, donnant vie à l'application.
- **Micro-Animations Fluides :** Interface réactive avec des animations basées sur l'état pour chaque interaction (lecture, agrandissement du lecteur, etc.).
- **Mises en page Dynamiques :** Un écran de lecture complet entièrement responsif, un mini-lecteur élégant et une file d'attente interactive par glisser-déposer.

### 🎧 Moteur de Lecture sans compromis
- **Cœur `AVPlayer` Natif :** Exploite le framework audio robuste d'Apple pour un streaming audio fiable et de haute qualité.
- **Intégration Système Profonde :** Prise en charge complète de l'audio en arrière-plan, synchronisation des métadonnées sur l'écran de verrouillage et commandes natives du Centre de contrôle (`MPRemoteCommandCenter`).
- **Gestion Intelligente de la File d'Attente :** Système avancé supportant les modes aléatoire, répétition, insertion dynamique de pistes et transitions quasi sans blanc.

### 🔍 Découverte & Bibliothèque (API InnerTube)
- **Flux d'Accueil Personnalisé :** Un flux dynamique exploitant le point de terminaison `FEmusic_home` de YouTube Music, intelligemment fusionné avec votre historique d'écoute local.
- **Recherche Ultra-Rapide :** Recherche avec auto-complétion et debounce de 350 ms, offrant instantanément des résultats regroupés (Chansons, Albums, Artistes, Playlists, Vidéos).
- **Métadonnées Orientées Hors-Ligne :** Mise en cache locale de vos Favoris, de votre Historique et des données de votre Bibliothèque à l'aide de **SwiftData** pour des temps de chargement instantanés.

### 🎤 Intégration de Paroles Immersives
- **Écosystème LRCLib :** Intégration native avec le projet open-source LRCLib.
- **Synchronisation en Temps Réel :** Prend en charge les paroles simples et synchronisées dans le temps, avec surlignage ligne par ligne directement dans le lecteur.

---

## 🛠️ Plongée dans l'Architecture

MusicGlass est conçu en gardant à l'esprit l'évolutivité, la maintenabilité et les modèles de développement iOS modernes. Il utilise une architecture modulaire hautement découplée :

### 1. Couche `App` & `UI`
- **Point d'Entrée :** La racine de l'application repose sur un conteneur d'Injection de Dépendances propre.
- **Navigation :** Navigation basée sur l'état gérant les feuilles (sheets) du lecteur global superposées à la vue principale.
- **Design System :** Composants UI réutilisables et matériaux de secours pour le "Liquid Glass" assurant une rétrocompatibilité avec iOS 17.

### 2. Fonctionnalités (`Features` - MVVM)
Chaque fonctionnalité principale (Accueil, Recherche, Bibliothèque, Lecteur, Paroles, Paramètres) est séparée dans son propre module contenant des écrans SwiftUI et des ViewModels rigoureusement testés.

### 3. Moteur de Lecture (`Playback`)
Une couche isolée encapsulant `AVPlayer` et `AVAudioSession`.
- Gère les mises à jour du `NowPlayingInfoCenter`.
- Gère la logique de la `PlayerQueue` (pistes à venir, pile d'historique).
- S'occupe du nettoyage du cache et du cycle de vie des ressources.

### 4. YouTubeMusic (Client InnerTube)
Un client réseau sur-mesure et très permissif s'interfaçant avec les API internes de YouTube.
- **Mapping JSON Défensif :** Utilise des parseurs et des DTOs personnalisés conçus pour gérer gracieusement les changements non annoncés de la structure de l'API.
- **Service de Paroles :** Récupère et synchronise les métadonnées externes sans interrompre la lecture.

### 5. Réseau (`Networking`) & `Core`
- **HTTPClient :** Un wrapper léger autour d'`URLSession` fournissant des primitives de requête async/await.
- **Logger Réseau Sécurisé :** Un système de journalisation personnalisé qui garantit que les jetons sensibles (SAPISID, en-têtes d'autorisation) ne fuient jamais dans la console.

### 6. Persistance (`Persistence`)
Entièrement propulsée par **SwiftData**.
- Dépôts (Repositories) pour gérer les enregistrements locaux (Favoris, Historique, Playlists personnalisées).
- Gère la mise en cache des métadonnées pour réduire les allers-retours réseau inutiles.

---

## 📦 Installation & Configuration

1. Clonez le dépôt et ouvrez `MusicGlass.xcodeproj` dans **Xcode 26.4** ou plus récent.
2. Sélectionnez le schéma `MusicGlass`.
3. Compilez et lancez sur un appareil ou simulateur sous **iOS 26+** pour l'expérience Liquid Glass complète. *(iOS 17/18 propose une alternative matérielle)*.

### Vérification de build en CLI

```bash
xcodebuild -project MusicGlass.xcodeproj -target MusicGlass -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MusicGlass.xcodeproj -target MusicGlassTests -configuration Debug -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

*Note : L'application nécessite un accès réseau pour la découverte et la lecture. L'audio en arrière-plan est activé via `UIBackgroundModes`.*

---

## 🛣️ Roadmap (Feuille de route)

- [ ] **Authentification :** Connexion sécurisée à YouTube Music via le Keychain.
- [ ] **Synchronisation de la Bibliothèque :** Synchronisation distante des chansons, albums, artistes et playlists.
- [ ] **Paroles Avancées :** Surlignage synchronisé des paroles façon karaoké et superposition de traduction.
- [ ] **Mode Hors-Ligne Intelligent :** Mise en cache des fichiers audio pour une véritable lecture hors ligne.
- [ ] **Intégration Écosystème :** Widgets iOS, Activités en Direct (Live Activities) et intégration potentielle de CarPlay/ShazamKit.
- [ ] **Fonctionnalités Sociales :** Scrobbling Last.fm et sessions d'écoute partagée via SharePlay.

---

## 🤝 Contribution

Les contributions, signalements de bugs et demandes de fonctionnalités sont les bienvenus ! 
Si vous trouvez un bug ou avez une suggestion, n'hésitez pas à consulter la [page des issues](https://github.com/jeremy99981/MusicGlass/issues).

1. Forkez le projet
2. Créez votre branche de fonctionnalité (`git checkout -b feature/AmazingFeature`)
3. Commitez vos changements (`git commit -m 'Add some AmazingFeature'`)
4. Poussez vers la branche (`git push origin feature/AmazingFeature`)
5. Ouvrez une Pull Request

---

<p align="center">
  <i>Conçu avec ❤️ pour les passionnés de musique et les développeurs Swift.</i>
</p>
