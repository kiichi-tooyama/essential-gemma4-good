import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android SpeechRecognizer bridge reports live STT availability',
    (tester) async {
      const channel = MethodChannel('essential/native_voice');
      final response = await channel.invokeMethod<Map<Object?, Object?>>(
        'getSpeechRecognizerState',
      );
      final state = Map<String, Object?>.from(
        response ?? const <Object?, Object?>{},
      );
      debugPrint(
        'ESSENTIAL_STT_STATE engine=${state['engine']} '
        'apiLevel=${state['apiLevel']} available=${state['available']} '
        'onDeviceAvailable=${state['onDeviceAvailable']} '
        'micPermission=${state['microphonePermissionGranted']}',
      );

      expect(state['engine'], 'android_speech_recognizer');
      expect(state['apiLevel'], isA<int>());
      expect(state.containsKey('available'), isTrue);
      expect(state.containsKey('onDeviceAvailable'), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'Live TTS bridge uses native MeloTTS audio for streaming chunks',
    (tester) async {
      const channel = MethodChannel('essential/native_voice');
      Future<Map<String, Object?>> speakLiveChunk(
        String text, {
        required String language,
        bool flush = false,
      }) async {
        final response = await channel.invokeMethod<Map<Object?, Object?>>(
          'speakChunk',
          <String, Object?>{
            'text': text,
            'language': language,
            'flush': flush,
            'engine': 'melotts',
            'sequenceId': 'integration-live-tts',
          },
        );
        final state = Map<String, Object?>.from(
          response ?? const <Object?, Object?>{},
        );
        debugPrint(
          'ESSENTIAL_TTS_STREAM_CHUNK_STATE chars=${text.runes.length} '
          'language=$language flush=$flush engine=${state['engine']} '
          'playbackEngine=${state['playbackEngine']} '
          'speaking=${state['speaking']} active=${state['activeUtterances']} '
          'utteranceId=${state['utteranceId']}',
        );
        return state;
      }

      await channel.invokeMethod<void>('stopSpeaking');
      final first = await speakLiveChunk(
        'Essential Live is generating ',
        language: 'en-US',
        flush: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final second = await speakLiveChunk(
        'and speaking at the same time.',
        language: 'en-US',
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final japanese = await speakLiveChunk(
        'こんにちは。Essential Liveです。',
        language: 'ja-JP',
      );
      final activeResponse = await channel.invokeMethod<Map<Object?, Object?>>(
        'getTtsState',
      );
      final activeState = Map<String, Object?>.from(
        activeResponse ?? const <Object?, Object?>{},
      );
      debugPrint(
        'ESSENTIAL_TTS_STREAM_ACTIVE_STATE '
        'engine=${activeState['engine']} '
        'playbackEngine=${activeState['playbackEngine']} '
        'speaking=${activeState['speaking']} '
        'active=${activeState['activeUtterances']}',
      );

      for (final state in <Map<String, Object?>>[first, second, japanese]) {
        expect(state['engine'], 'melotts');
        expect(state['nativeMeloTtsAvailable'], isTrue);
        expect(state['playbackEngine'], 'melotts_native_audio');
        expect(state['utteranceId'], isA<String>());
      }
      expect(activeState['engine'], 'melotts');
      expect(activeState['playbackEngine'], 'melotts_native_audio');
      await channel.invokeMethod<void>('stopSpeaking');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
