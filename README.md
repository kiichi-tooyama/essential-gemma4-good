# Essential Production Submission Repository

This folder is a source-only release repository prepared for production
submission review. It intentionally does not include APK or AAB artifacts.

## Open In Android Studio

Main Essential app:

```bash
open apps/essential_flutter/android
```

Pixel Feature Chat and SDK demos:

```bash
open packages/essential_android_sdk
```

From Android Studio, choose a connected Android device and run the desired debug
configuration. The main Flutter app can also be installed from the terminal:

```bash
cd apps/essential_flutter
flutter run --flavor standard
```

The Pixel Feature Chat demo can be installed after the main Essential app:

```bash
cd packages/essential_android_sdk
./gradlew :pixel_chat_app:installDebug
```

## Production Notes

- Main Essential launcher icons use the blue and green gradient mark in square
  and round Android launcher assets.
- Pixel Feature Chat launcher icons use the black and white chat mark in square
  and round Android launcher assets.
- The app starts in English by default and can switch to Japanese from Settings.
- The Flutter debug banner is disabled.
- Release builds are not signed with debug keys in this source repository.
- The exported Essential service is protected by a signature permission, and
  cleartext network traffic is disabled for the main app.

## Included Source

- `apps/essential_flutter`: main Android/Flutter app.
- `packages/essential_android_sdk`: local Android SDK and demo apps, including
  Pixel Feature Chat.
- `packages/essential_sdk_dart`: Flutter app runtime SDK dependency.
- `native` and `third_party`: native inference, audio, vision, Whisper, Vulkan,
  and SPIR-V sources required by the Android build.
- `docs`: submission and implementation documentation.
