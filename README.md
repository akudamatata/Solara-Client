# Solara Native Flutter Client

This project rebuilds the Solara music experience as a first-class Flutter application that mirrors the vertical iOS layout from [akudamatata/Solara](https://github.com/akudamatata/Solara). Instead of wrapping the web player, the app renders native widgets, talks directly to `https://music-api.gdstudio.xyz/api.php`, and exposes player controls, playlists, favourites, search, and quality switching with a mobile-first feel.

## Project layout

- `lib/main.dart` – Flutter app (widgets + controllers) that renders the Solara UI natively and talks to the direct music API.
- `tool/package_unsigned_ipa.sh` – helper that zips the built `Runner.app` into an unsigned IPA and copies the dSYM for distribution.
- `ios/` – Runner target configured with the bundle identifier `com.wetdreamboy.solara`, portrait-only, ATS exceptions for localhost, and AppStore-ready settings.
- `android/` – kept in sync with the same applicationId for parity/testing.
- `.github/workflows/ios-build.yml` – GitHub Actions workflow that produces an unsigned IPA artifact with `flutter build ios --release --no-codesign` and a packaging helper script.

## Requirements

- Flutter 3.3+ (stable channel). Install from [flutter.dev](https://docs.flutter.dev/get-started/install) and add `flutter/bin` to `PATH`.
- Xcode 15+ with command-line tools for local iOS builds.
- (Optional) CocoaPods for manual `pod install` inside `ios/`.

## Local development

```bash
flutter pub get
flutter run -d ios        # or any connected simulator

# Generate an unsigned IPA locally (requires macOS + Xcode)
flutter build ios --release --no-codesign
bash tool/package_unsigned_ipa.sh
```

### Core architecture

- `SolaraApi` (inside `lib/main.dart`) issues signed GET requests directly to `https://music-api.gdstudio.xyz/api.php` with the same parameters as the original web implementation.
- `SolaraPlayerController` manages queue playback through `just_audio`, handles quality changes (128k / 192k / 320k / FLAC), caches album artwork + lyrics, and exposes derived UI state.
- `SolaraSearchController` mirrors the mobile search overlay – it supports source switching (网易云 / QQ / 酷狗 / 咪咕), multi-select import into the queue, and one-tap preview.
- Native widgets recreate the Solara mobile layout: gradient shell, album art halo, progress slider, toolbar, playlist & favourite panels, and the modal search sheet.

## GitHub Actions (unsigned IPA)

The workflow `.github/workflows/ios-build.yml` does the following whenever triggered manually or on pushes to `main`:

1. Checks out the repo.
2. Installs Flutter via `subosito/flutter-action`.
3. Runs `flutter pub get`.
4. Builds an unsigned iOS app bundle with `flutter build ios --release --no-codesign`.
5. Packages the bundle into `build/ios/ipa/Runner.ipa` via `tool/package_unsigned_ipa.sh` and uploads it together with the debug symbols.

Download the artifact from the workflow run page, unzip, and distribute/sign as needed.

## Support / next steps

- Hook in offline caching or downloads once storage/licensing requirements are clear.
- Integrate lyrics display or background blur derived from `SolaraPlayerController.currentLyrics`.
- Connect a CI/CD provider (Fastlane, Codemagic) if you need signed builds or TestFlight uploads.
