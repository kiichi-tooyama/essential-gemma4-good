# Essential Gemma 4 Good Public Package

This release is the current upload-ready package for the hackathon demo assets.
It keeps the same public repository format and updates only the submitted app
sources, sample files, and release APKs required for the latest demo.

## APK

- GitHub Release `v1.0.10` asset `app-release.apk`: latest Essential Android app.
- GitHub Release `v1.0.10` asset `pixel_chat_app-release.apk`: Pixel Feature Chat release APK signed with the same certificate as Essential.
- GitHub Release `v1.0.10` asset `essential-gemma4-good-v1.0.10-source.zip`: explicit source zip for the latest submitted source tree.

## Demo Code To Show On PC

- `source_samples/PixelFeatureChatDemo.kt`: minimal API usage sample.
- `source_samples/PixelChatMainActivity.kt`: actual Pixel Feature Chat demo app.
- `source_samples/pixel_feature_guide.txt`: bundled Pixel Feature Chat reference data.
- `packages/essential_android_sdk/pixel_chat_app`: buildable Pixel Feature Chat Android app.

## Models

The app supports server download and bundled test model flows. This workspace did
not currently contain Gemma `.litertlm` model binaries, so this package includes
model terms and placement notes but not the Gemma model files themselves. If
model binaries are added before upload, place them under `models/`, add SHA-256
checksums to `models/MODEL_MANIFEST.txt`, and keep the Google Gemma terms with
this package.

## Licensing

Original Essential code, documentation, demos, and project materials are
licensed under CC BY 4.0. See the repository-root `LICENSE` file. Third-party
OSS, SDKs, generated binaries, and model files remain under their own licenses
and terms.


## 2026-05-12 Update

- Removed the accidental working-repository layout from the public repo.
- Kept the root Flutter public format used by the previous submission.
- Updated Essential icons, language switching, Debug banner handling, and Android security settings.
- Updated Pixel Feature Chat sample data and refreshed release APK assets.


## 2026-05-12 Repair Update

- Restored the previous public repository format after the accidental working-tree upload.
- Applied only the Essential app updates needed for submission: icons, language switching, Debug banner removal, HTTPS registry default, and Android security hardening.
- Refreshed the GitHub Release APK as `app-release.apk`.

## 2026-05-12 Pixel Feature Chat Update

- Added the buildable Android SDK / Pixel Feature Chat package to the public repo.
- Kept Essential's signature-protected service permission and made same-certificate release signing a required check.
- Added `scripts/verify_android_release_signatures.sh` to prevent Essential and Pixel Chat release APKs from being published with mismatched signing certificates.
- Added Android Gradle wrapper files so a fresh GitHub checkout can sync and install from Android Studio without relying on untracked local files.

## 2026-05-13 Android Studio Build Repair

- Pinned the public Android Gradle projects to Homebrew JDK 21 so a Mac with default JDK 25 can still sync and build from Android Studio.
- Added release signing configuration to the main Essential APK so release assets install on Pixel devices with the same certificate as Pixel Feature Chat.
- Bumped both APKs to version `1.0.10` / versionCode `10`.
- Added automatic `flutter pub get` before Flutter Android Gradle compile tasks so Android Studio builds work from a fresh GitHub ZIP even when `.dart_tool/package_config.json` does not exist yet.
- Added the same dependency preparation in Android Gradle settings so Flutter plugins are included during the first Android Studio sync/build.
- Main Android Gradle builds now read the APK version directly from `pubspec.yaml`, so Android Studio builds and `flutter build apk` produce the same version.
