import 'package:flutter/widgets.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 80;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 24 << 20;
  const smokeFlowEnabled = bool.fromEnvironment('ESSENTIAL_ENABLE_SMOKE_FLOW');
  const smokeModelPath = String.fromEnvironment('ESSENTIAL_SMOKE_MODEL_PATH');
  const smokePrompt = String.fromEnvironment(
    'ESSENTIAL_SMOKE_PROMPT',
    defaultValue: 'Write one short sentence about a red kite.',
  );
  const smokePrompts = String.fromEnvironment('ESSENTIAL_SMOKE_PROMPTS');
  const smokeImagePaths = String.fromEnvironment('ESSENTIAL_SMOKE_IMAGE_PATHS');
  const smokeAudioPaths = String.fromEnvironment('ESSENTIAL_SMOKE_AUDIO_PATHS');
  runApp(
    EssentialApp(
      smokeModelPath: smokeFlowEnabled && smokeModelPath.isNotEmpty
          ? smokeModelPath
          : null,
      smokePrompt: smokePrompt,
      smokePrompts: smokePrompts.isEmpty
          ? const <String>[]
          : smokePrompts.split('|||'),
      smokeImagePaths: smokeImagePaths.isEmpty
          ? const <String>[]
          : smokeImagePaths.split('|||'),
      smokeAudioPaths: smokeAudioPaths.isEmpty
          ? const <String>[]
          : smokeAudioPaths.split('|||'),
    ),
  );
}
