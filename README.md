# Solara iOS Shell

Flutter wrapper that delivers the Solara web music player as a polished, portrait-only iOS (and Android) experience. The original web assets from [akudamatata/solara](https://github.com/akudamatata/solara) ship inside the app and are rendered through a full-screen `InAppWebView`, so the UI and functionality stay 1:1 with the design shown in the screenshots.

## Project layout

- `assets/solara_web/` – untouched Solara web build (HTML, CSS, JS, preview GIF, etc.).
- `lib/main.dart` – Flutter shell that boots a local server, injects the page into a rounded "device" frame, and handles loading/error states.
- `ios/` – Runner target configured with the bundle identifier `com.wetdreamboy.solara`, portrait-only, ATS exceptions for localhost, and AppStore-ready settings.
- `android/` – kept in sync with the same applicationId for parity/testing.
- `.github/workflows/ios-build.yml` – GitHub Actions workflow that produces an unsigned IPA artifact with `flutter build ipa --no-codesign`.

## Requirements

- Flutter 3.3+ (stable channel). Install from [flutter.dev](https://docs.flutter.dev/get-started/install) and add `flutter/bin` to `PATH`.
- Xcode 15+ with command-line tools for local iOS builds.
- (Optional) CocoaPods for manual `pod install` inside `ios/`.

## Local development

```bash
flutter pub get
flutter run -d ios        # or any connected simulator

# Generate an unsigned IPA locally (requires macOS + Xcode)
flutter build ipa --no-codesign --export-options-plist=ios/Flutter/exportOptions.plist
```

The Flutter layer spins up an embedded localhost server (port `8079`) that serves `assets/solara_web/index.html`. Hot reloading works when editing the Flutter wrapper; changes to the HTML/JS assets require a full rebuild.

### Customizing the embedded player

- Replace/modify files inside `assets/solara_web/` (e.g., update playlists, tweak CSS).
- Declare any new asset folders in `pubspec.yaml` under the `assets:` section.
- If the Solara JS starts new network requests, remember to whitelist the domains under `NSAppTransportSecurity` if they are non-HTTPS.

## GitHub Actions (unsigned IPA)

The workflow `.github/workflows/ios-build.yml` does the following whenever triggered manually or on pushes to `main`:

1. Checks out the repo.
2. Installs Flutter via `subosito/flutter-action`.
3. Runs `flutter pub get`.
4. Builds an unsigned IPA with `flutter build ipa --no-codesign`.
5. Uploads `build/ios/archive/Runner.xcarchive` and the generated IPA as artifacts.

Download the artifact from the workflow run page, unzip, and distribute/sign as needed.

## Support / next steps

- Add authentication or API keys by injecting runtime values into the Solara JS bundle.
- Extend the Flutter shell with native overlays (mini player, playback controls, deep links).
- Connect a CI/CD provider (Fastlane, Codemagic) if you need signed builds or TestFlight uploads.
