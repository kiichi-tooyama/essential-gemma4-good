import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'audio_message_widget.dart';

const _voiceRecorderConfig = RecordConfig(
  encoder: AudioEncoder.wav,
  sampleRate: 16000,
  numChannels: 1,
);

class VoiceRecordingScreen extends StatefulWidget {
  const VoiceRecordingScreen({super.key});

  @override
  State<VoiceRecordingScreen> createState() => _VoiceRecordingScreenState();
}

class _VoiceRecordingScreenState extends State<VoiceRecordingScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  String? _path;
  String _transcription = '';
  bool _recording = false;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('マイク権限がありません。')));
      }
      return;
    }
    if (!await _recorder.isEncoderSupported(AudioEncoder.wav)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('WAV PCM 録音に対応していません。')));
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(_voiceRecorderConfig, path: path);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
    setState(() {
      _path = path;
      _recording = true;
      _elapsed = Duration.zero;
      _transcription = '聞き取り中…';
    });
  }

  Future<void> _stop({bool cancel = false}) async {
    final path = await _recorder.stop();
    _timer?.cancel();
    if (!mounted) {
      return;
    }
    if (cancel) {
      if (path != null) {
        await File(path).delete().catchError((_) => File(path));
      }
      setState(() {
        _path = null;
        _recording = false;
        _transcription = '';
      });
      return;
    }
    setState(() {
      _path = path ?? _path;
      _recording = false;
      _transcription = '音声メッセージ';
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    return Scaffold(
      appBar: AppBar(title: const Text('音声入力')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: <Widget>[
              const Spacer(),
              RecordingControl(
                transcription: _transcription,
                onFinished: (sendable) {
                  if (_recording) {
                    _stop(cancel: !sendable);
                  }
                },
              ),
              const SizedBox(height: 18),
              Text(
                _format(_elapsed),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 12),
              Text(_recording ? '上にスライドでキャンセル' : '長押しで録音'),
              const Spacer(),
              if (!_recording && path != null)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop<String>(null),
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('破棄'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop<String>(path),
                        icon: const Icon(Icons.send_rounded),
                        label: const Text('音声で送信'),
                      ),
                    ),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: _recording ? () => _stop() : _start,
                  icon: Icon(
                    _recording ? Icons.stop_rounded : Icons.mic_rounded,
                  ),
                  label: Text(_recording ? '停止' : '録音開始'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
