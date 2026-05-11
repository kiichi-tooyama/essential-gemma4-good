import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:essential_flutter/features/model_management/model_management_controller.dart';
import 'package:essential_flutter/features/meeting_assistant/meeting_controller.dart';
import 'package:essential_flutter/features/meeting_assistant/meeting_models.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Meeting processing pipeline test', (tester) async {
    // 1. Initialize controllers
    await _seedModelsFromLocalTmp();
    final modelController = ModelManagementController.createDefault();
    await modelController.initialize();

    final meetingController = MeetingController(
      modelController: modelController,
    );
    await meetingController.initialize();

    // 2. Mock or use actual file
    final File audioFile = File(
      File('/data/local/tmp/meeting.wav').existsSync()
          ? '/data/local/tmp/meeting.wav'
          : '/sdcard/Download/meeting.wav',
    );
    if (!audioFile.existsSync()) {
      debugPrint('Skipping test: /sdcard/Download/meeting.wav not found.');
      return;
    }

    // 3. Process meeting
    debugPrint('Starting processMeeting...');
    await meetingController.processMeeting(
      audioFile.path,
      false,
      recordingSource: 'integration_test_with_transcript',
      initialTranscription:
          'This test transcript is supplied with the meeting audio. '
          'The team discusses Essential, Gemma 4 LiteRT-LM, web search, '
          'location-aware answers, external SDK access, image input, '
          'live voice input, spoken output, and the next submission tasks.',
    );

    // Wait for processing to complete
    final session = meetingController.sessions.first;
    expect(session.status, MeetingStatus.processing);

    debugPrint('Waiting for processing to complete...');

    int timeout = 300; // 5 mins
    while (meetingController.sessions.first.status ==
            MeetingStatus.processing &&
        timeout > 0) {
      await Future<void>.delayed(const Duration(seconds: 1));
      timeout--;
    }

    final completedSession = meetingController.sessions.first;
    debugPrint('Finished with status: ${completedSession.status}');
    debugPrint('Summary: ${completedSession.summary}');
    debugPrint('Transcription: ${completedSession.transcription}');

    expect(completedSession.status, MeetingStatus.completed);
    expect(completedSession.transcription, isNotEmpty);
    expect(completedSession.summary, isNotEmpty);

    // 4. Test meeting consultation through the same app route.
    debugPrint('Testing meeting consultation...');
    final answer = await meetingController.askMeetingQuestion(
      completedSession,
      'この会議の次のタスクを短く整理して',
      useWeb: false,
    );

    debugPrint('Consultation Response: $answer');
    expect(answer, isNotEmpty);
  });
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
