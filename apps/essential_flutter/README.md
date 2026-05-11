# Essential Flutter

## llama.cpp integration smoke test

1. `cd apps/essential_flutter`
2. `bash tool/download_smoke_model.sh`
3. `flutter run -d macos --dart-define=ESSENTIAL_ENABLE_SMOKE_FLOW=true --dart-define=ESSENTIAL_SMOKE_MODEL_PATH=$(pwd)/test_models/tinystories-gpt-0.1-3m.Q2_K.gguf`

The app opens on the inference screen, loads the GGUF model through the FFI bridge, and prints `ESSENTIAL_SMOKE_RESULT=` to the debug console after streaming generation completes.

## Local registry for model downloads

Start the development registry before opening the Models tab:

```bash
cd ../..
pip3 install -r server/registry_api/requirements.txt
PYTHONPATH=server/common uvicorn server.registry_api.app:app --host 127.0.0.1 --port 8100
```

Default registry URL:

- `http://210.131.210.210`

Override the registry URL at build or run time when needed:

```bash
flutter run --dart-define=ESSENTIAL_REGISTRY_URL=http://210.131.210.210
flutter build apk --dart-define=ESSENTIAL_REGISTRY_URL=http://210.131.210.210
```

For a local development registry, pass a reachable host URL, for example `--dart-define=ESSENTIAL_REGISTRY_URL=http://10.0.2.2:8100` for Android emulator, and start the registry with `--host 0.0.0.0` when using physical devices.

## iOS EssentialKit integration

- `ios/Podfile` now links local `EssentialKit` and `AppGroupSupport` pods.
- `Runner/Runner.entitlements` enables App Group sharing via `group.$(PRODUCT_BUNDLE_IDENTIFIER).shared`.
- On launch, `Runner/AppDelegate.swift` initializes `EssentialClient` and synchronizes Flutter model metadata into the shared App Group registry.
