import 'dart:convert';
import 'dart:io';

import 'package:essential_flutter/features/meeting_assistant/meeting_controller.dart';
import 'package:essential_flutter/features/meeting_assistant/meeting_models.dart';
import 'package:essential_flutter/features/model_management/model_management_controller.dart';
import 'package:essential_flutter/features/shared/audio_tools_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'meeting assistant transcribes an existing mp3 with Whisper',
    (tester) async {
      await _seedModelsFromLocalTmp();
      const sourcePath = '/data/local/tmp/essential-meeting-test.mp3';
      expect(
        File(sourcePath).existsSync(),
        isTrue,
        reason: '$sourcePath missing',
      );

      final normalized = await const AudioToolsService().normalizeToSpeechWav(
        sourcePath,
        maxDuration: const Duration(seconds: 45),
      );
      final header = await File(normalized).openRead(0, 12).first;
      debugPrint(
        'ESSENTIAL_EXISTING_MP3_NORMALIZE_RESULT source=$sourcePath normalized=$normalized',
      );
      expect(String.fromCharCodes(header.take(4)), 'RIFF');
      expect(String.fromCharCodes(header.skip(8).take(4)), 'WAVE');
      final meetingInput = normalized;
      debugPrint(
        'ESSENTIAL_EXISTING_MP3_MEETING_INPUT path=$meetingInput size=${File(meetingInput).lengthSync()}',
      );

      final modelController = ModelManagementController.createDefault();
      await modelController.initialize();
      final meetingController = MeetingController(
        modelController: modelController,
      );
      addTearDown(meetingController.dispose);
      await meetingController.initialize();
      await meetingController.processMeeting(
        meetingInput,
        false,
        recordingSource: 'import_whisper',
      );

      var remainingSeconds = 900;
      while (remainingSeconds > 0 &&
          meetingController.sessions.isNotEmpty &&
          meetingController.sessions.first.status == MeetingStatus.processing) {
        await Future<void>.delayed(const Duration(seconds: 1));
        remainingSeconds -= 1;
      }

      final session = meetingController.sessions.first;
      debugPrint(
        'ESSENTIAL_EXISTING_MP3_MEETING_RESULT status=${session.status.name} '
        'summaryChars=${session.summary.runes.length} transcriptionChars=${session.transcription.runes.length} '
        'translations=${session.translations.keys.join(",")}',
      );
      debugPrint(
        'ESSENTIAL_EXISTING_MP3_TRANSCRIPTION_HEAD=${_takeRunes(session.transcription, 220)}',
      );
      debugPrint(
        'ESSENTIAL_EXISTING_MP3_SUMMARY_HEAD=${_takeRunes(session.summary, 220)}',
      );
      expect(session.status, MeetingStatus.completed);
      expect(session.transcription.trim(), isNotEmpty);
      expect(session.summary.trim(), isNotEmpty);
      expect(session.translations['en']?.trim(), isNotEmpty);
      expect(session.translations['zh']?.trim(), isNotEmpty);
      expect(session.translations['ko']?.trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<void> _seedModelsFromLocalTmp() async {
  final source = Directory('/data/local/tmp/essential_model_seed');
  if (!source.existsSync()) {
    debugPrint('ESSENTIAL_MODEL_SEED_SKIPPED source_missing=${source.path}');
    return;
  }
  final support = await getApplicationSupportDirectory();
  final target = Directory(path.join(support.path, 'essential_models'));
  final metadata = File(path.join(target.path, 'metadata.json'));
  if (metadata.existsSync()) {
    try {
      final payload =
          jsonDecode(await metadata.readAsString()) as Map<String, dynamic>;
      final installations =
          payload['installations'] as List<dynamic>? ?? const <dynamic>[];
      if (installations.length >= 8) {
        debugPrint('ESSENTIAL_MODEL_SEED_READY existing=${target.path}');
        return;
      }
    } catch (_) {}
  }
  if (target.existsSync()) {
    await target.delete(recursive: true);
  }
  await _copyDirectory(source, target);
  debugPrint('ESSENTIAL_MODEL_SEED_COPIED target=${target.path}');
}

Future<void> _copyDirectory(Directory source, Directory target) async {
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: false)) {
    final name = path.basename(entity.path);
    final nextPath = path.join(target.path, name);
    if (entity is Directory) {
      await _copyDirectory(entity, Directory(nextPath));
    } else if (entity is File) {
      await entity.copy(nextPath);
    }
  }
}

String _takeRunes(String text, int count) {
  if (text.runes.length <= count) {
    return text;
  }
  return String.fromCharCodes(text.runes.take(count));
}
