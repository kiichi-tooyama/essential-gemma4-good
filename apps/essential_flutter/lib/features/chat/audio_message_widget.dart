import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'chat_controller.dart';

class AudioMessageWidget extends StatefulWidget {
  const AudioMessageWidget({required this.attachment, super.key});

  final ChatAttachment attachment;

  @override
  State<AudioMessageWidget> createState() => _AudioMessageWidgetState();
}

class _AudioMessageWidgetState extends State<AudioMessageWidget> {
  late final AudioPlayer _player = AudioPlayer();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    final path = widget.attachment.filePath;
    if (path != null) {
      try {
        final duration = await _player.setFilePath(path);
        if (mounted) {
          setState(() => _duration = duration ?? Duration.zero);
        }
      } catch (_) {}
    }
    _player.positionStream.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 260),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton.filledTonal(
                onPressed: widget.attachment.filePath == null ? null : _toggle,
                icon: Icon(
                  _player.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                tooltip: _player.playing ? '一時停止' : '再生',
              ),
              Expanded(
                child: GestureDetector(
                  onTapDown: (details) {
                    if (_duration == Duration.zero) {
                      return;
                    }
                    final width = context.size?.width ?? 1;
                    final ratio = (details.localPosition.dx / width).clamp(
                      0,
                      1,
                    );
                    _player.seek(_duration * ratio);
                  },
                  child: SizedBox(
                    height: 44,
                    child: CustomPaint(
                      painter: _WaveformPainter(
                        progress: _duration == Duration.zero
                            ? 0
                            : _position.inMilliseconds /
                                  _duration.inMilliseconds,
                        color: scheme.primary,
                        background: scheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${_format(_position)} / ${_format(_duration)}'),
            ],
          ),
          if (widget.attachment.transcription?.isNotEmpty ?? false) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              widget.attachment.transcription!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (widget.attachment.isProcessing) ...<Widget>[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  String _format(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class RecordingControl extends StatefulWidget {
  const RecordingControl({
    required this.onFinished,
    this.transcription,
    super.key,
  });

  final ValueChanged<bool> onFinished;
  final String? transcription;

  @override
  State<RecordingControl> createState() => _RecordingControlState();
}

class _RecordingControlState extends State<RecordingControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.92,
    upperBound: 1.08,
  );
  bool _recording = false;

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _start() {
    setState(() => _recording = true);
    _pulse.repeat(reverse: true);
  }

  void _stop({bool cancelled = false}) {
    _pulse.stop();
    setState(() => _recording = false);
    widget.onFinished(!cancelled);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GestureDetector(
          onLongPressStart: (_) => _start(),
          onLongPressEnd: (_) => _stop(),
          onVerticalDragEnd: (_) => _stop(cancelled: true),
          child: ScaleTransition(
            scale: _pulse,
            child: Icon(
              Icons.mic_rounded,
              size: 72,
              color: _recording
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        if (widget.transcription?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(widget.transcription!),
          ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.progress,
    required this.color,
    required this.background,
  });

  final double progress;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final activePaint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    final inactivePaint = Paint()
      ..color = background
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3;
    const bars = 36;
    for (var i = 0; i < bars; i++) {
      final x = size.width * (i / (bars - 1));
      final seed = ((i * 37) % 17) / 17;
      final height = size.height * (0.24 + seed * 0.62);
      final paint = i / bars <= progress ? activePaint : inactivePaint;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.background != background;
  }
}
