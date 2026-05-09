import 'dart:io';

import 'package:flutter/material.dart';

import 'chat_controller.dart';

class ImageMessageWidget extends StatelessWidget {
  const ImageMessageWidget({
    required this.attachment,
    required this.isUser,
    super.key,
  });

  final ChatAttachment attachment;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final filePath = attachment.filePath;
    final tag = 'chat-image-${attachment.id}';
    final analysisLabels = _visibleOverlayLabels(attachment.analysisLabels);
    final detectedObjects = _visibleOverlayLabels(attachment.detectedObjects);
    final image = filePath == null
        ? const ColoredBox(color: Colors.black12)
        : Image.file(File(filePath), fit: BoxFit.cover);
    return GestureDetector(
      onTap: filePath == null
          ? null
          : () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _FullscreenImage(path: filePath, tag: tag),
                ),
              );
            },
      onLongPress: () => _showOptions(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: <Widget>[
            Hero(
              tag: tag,
              child: AspectRatio(aspectRatio: 4 / 3, child: image),
            ),
            if (attachment.isProcessing)
              const Positioned.fill(child: _AnalysisShimmer()),
            if (analysisLabels.isNotEmpty || detectedObjects.isNotEmpty)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final label in analysisLabels)
                      _OverlayChip(label: label),
                    for (final object in detectedObjects)
                      _OverlayChip(label: object),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showOptions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text('保存'),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('共有'),
                onTap: () => Navigator.of(context).pop(),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('削除'),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  List<String> _visibleOverlayLabels(List<String> labels) {
    return labels
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .where(
          (label) =>
              !label.contains('Exception') &&
              !label.contains('RUNTIME_UNAVAILABLE') &&
              !label.contains('runtime unavailable') &&
              !label.contains('Vision runtime'),
        )
        .toList(growable: false);
  }
}

class _FullscreenImage extends StatelessWidget {
  const _FullscreenImage({required this.path, required this.tag});

  final String path;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Hero(
          tag: tag,
          child: InteractiveViewer(child: Image.file(File(path))),
        ),
      ),
    );
  }
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}

class _AnalysisShimmer extends StatefulWidget {
  const _AnalysisShimmer();

  @override
  State<_AnalysisShimmer> createState() => _AnalysisShimmerState();
}

class _AnalysisShimmerState extends State<_AnalysisShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + _controller.value * 2, -1),
              end: Alignment(_controller.value * 2, 1),
              colors: <Color>[
                Colors.transparent,
                Colors.white.withValues(alpha: 0.28),
                Colors.transparent,
              ],
            ),
          ),
        );
      },
    );
  }
}
