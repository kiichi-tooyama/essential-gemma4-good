import 'dart:async';
import 'package:flutter/material.dart';
import 'meeting_controller.dart';
import 'meeting_enhancements.dart';

class MeetingRecordingScreen extends StatefulWidget {
  const MeetingRecordingScreen({required this.controller, super.key});

  final MeetingController controller;

  @override
  State<MeetingRecordingScreen> createState() => _MeetingRecordingScreenState();
}

class _MeetingRecordingScreenState extends State<MeetingRecordingScreen> {
  bool _isRecording = false;
  bool _isInternal = false;
  int _elapsedSeconds = 0;
  Timer? _timer;
  final List<MeetingBookmark> _bookmarks = <MeetingBookmark>[];

  @override
  void dispose() {
    _timer?.cancel();
    if (_isRecording) {
      if (_isInternal) {
        widget.controller.stopInternalRecording();
      } else {
        widget.controller.stopMicRecording();
      }
    }
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop
      _timer?.cancel();
      setState(() {
        _isRecording = false;
      });
      final path = _isInternal
          ? await widget.controller.stopInternalRecording()
          : await widget.controller.stopMicRecording();

      if (path != null && mounted) {
        widget.controller.processMeeting(
          path,
          _isInternal,
          recordingSource: _isInternal ? 'internal_audio' : 'mic',
          initialBookmarks: _bookmarks,
        );
        Navigator.of(context).pop();
      }
    } else {
      // Start
      bool success = false;
      if (_isInternal) {
        success = await widget.controller.startInternalRecording();
      } else {
        await widget.controller.startMicRecording();
        success = true;
      }

      if (success) {
        setState(() {
          _isRecording = true;
          _elapsedSeconds = 0;
          _bookmarks.clear();
        });
        _startTimer();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.controller.strings;
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('meeting.recording.title'))),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_isRecording) ...[
              Text(strings.t('meeting.recording.chooseSource')),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ChoiceChip(
                    label: Text(strings.t('meeting.recording.mic')),
                    selected: !_isInternal,
                    onSelected: (val) {
                      if (val) setState(() => _isInternal = false);
                    },
                  ),
                  const SizedBox(width: 16),
                  ChoiceChip(
                    label: Text(strings.t('meeting.recording.device')),
                    selected: _isInternal,
                    onSelected: (val) {
                      if (val) setState(() => _isInternal = true);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 64),
            ],

            Text(
              '$minutes:$seconds',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: _isRecording ? Colors.red : null,
              ),
            ),
            const SizedBox(height: 64),

            if (_isRecording) ...[
              FilledButton.icon(
                onPressed: _addBookmark,
                icon: const Icon(Icons.bookmark_add_rounded),
                label: Text(
                  '${strings.t('meeting.recording.bookmark')} (${_bookmarks.length})',
                ),
              ),
              const SizedBox(height: 24),
            ],

            GestureDetector(
              onTap: _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: _isRecording ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: _isRecording ? BorderRadius.circular(16) : null,
                  color: _isRecording
                      ? Colors.red
                      : Theme.of(context).colorScheme.primary,
                ),
                child: Center(
                  child: Icon(
                    _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addBookmark() {
    setState(() {
      _bookmarks.add(
        MeetingBookmark(
          id: 'bookmark-${DateTime.now().microsecondsSinceEpoch}',
          startSeconds: _elapsedSeconds.toDouble(),
          label: widget.controller.strings.t('meeting.recording.bookmark'),
          createdAt: DateTime.now(),
        ),
      );
    });
  }
}
