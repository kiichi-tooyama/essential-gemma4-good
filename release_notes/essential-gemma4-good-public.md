# Essential Gemma 4 Good Public Package

This release is the current upload-ready package for the hackathon demo assets.
It keeps the same public repository format and updates only the submitted app
sources, sample files, and release APKs required for the latest demo.

## APK

- GitHub Release `v1.0.2` asset `app-release.apk`: latest Essential Android app.

## Demo Code To Show On PC

- `source_samples/PixelFeatureChatDemo.kt`: minimal API usage sample.
- `source_samples/PixelChatMainActivity.kt`: actual Pixel Feature Chat demo app.
- `source_samples/pixel_feature_guide.txt`: bundled Pixel Feature Chat reference data.
- `source_samples/pixel_feature_guide.txt`: bundled Pixel Feature Chat reference data.

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
