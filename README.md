# Solara Native iOS Client

This repository now ships a fully native SwiftUI implementation of Solara. The app talks directly to `https://music-api.gdstudio.xyz/api.php`, manages playback with `AVPlayer`, and mirrors the original portrait layout with search, queue management, favourites, lyrics, and quality switching (128k / 192k / 320k / FLAC / 无损)。

## Project layout

- `Solara.xcodeproj` – Xcode project targeting iOS 17+, preconfigured for SwiftUI and background audio.
- `Solara/App` – App entry point and root UI container.
- `Solara/Models` – Data models for songs, quality, playback snapshots, and parsed lyrics.
- `Solara/Services` – API client, playback manager (AVFoundation + MPNowPlayingInfoCenter), and shared image loader.
- `Solara/ViewModels` – Observable view models (e.g., aggregated multi-source search).
- `Solara/Views` – SwiftUI screens, sheets, and reusable components.
- `Solara/Resources` – App assets, accent colour, launch screen storyboard, and `Info.plist` (app icon is generated at build time to avoid storing binaries).

## Key capabilities

- **Direct API access** – Signed GET requests to `music-api.gdstudio.xyz` with shared headers, Codable helpers, and async/await networking.
- **Playback service** – `PlaybackManager` wraps `AVPlayer`, handles queue play/pause/上一首/下一首, quality switching, seek, remote command center integration, and background metadata updates.
- **Multi-source search** – Concurrent searches across 网易云 / QQ / 酷我 / 酷狗 / 咪咕 with multi-select actions (enqueue or play now).
- **UI/UX** – Gradient shell, album art viewer, lyrics scroller, queue + favourites sheets, and quality/play mode menus implemented in SwiftUI.
- **State persistence** – Lightweight JSON snapshot for queue, favourites, playback mode, and position in Application Support.

## Local development

1. Open `Solara.xcodeproj` in Xcode 15+.
2. Select the **Solara** scheme and an iOS 17+ device/simulator.
3. Build & run (code signing is configured for automatic signing; adjust the team as needed).

## CI

`.github/workflows/ios-build.yml` builds the iOS target on `macos-latest` using `xcodebuild` with signing disabled. The job ensures the SwiftUI target stays compilable in CI.

## Notes / next steps

- Add richer animations or UIKit-powered components via `UIViewRepresentable` if desired.
- Extend persistence to cache artwork/audio files for offline playback using `FileManager`.
- Wire up advanced error handling and retry for unstable network conditions.
