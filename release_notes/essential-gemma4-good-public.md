# Essential Gemma 4 Good Public Package

This folder is the current upload-ready package for the hackathon demo assets.
It contains installable debug APKs, the 3-minute video script, narration-only
script, Kaggle writeup draft, generated media assets, and the external API code
sample shown in the demo.

## APKs

- `apks/essential-standard-debug.apk`: main Essential app.
- `apks/pixel-feature-chat-debug.apk`: separate Pixel Feature Chat API demo.
- `apks/essential-sdk-demo-debug.apk`: broader SDK demo app.
- `apks/plant-camera-debug.apk`: camera/image demo app.

## Demo Code To Show On PC

- `source_samples/PixelFeatureChatDemo.kt`: minimal API usage sample.
- `source_samples/PixelChatMainActivity.kt`: actual Pixel Feature Chat demo app.

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
