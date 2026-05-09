import 'dart:io';

import 'package:flutter/material.dart';

import 'chat_controller.dart';

class MultimodalComposer extends StatelessWidget {
  const MultimodalComposer({
    required this.attachments,
    required this.onRemove,
    super.key,
  });

  final List<ChatAttachment> attachments;
  final ValueChanged<ChatAttachment> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 10),
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          return _AttachmentTile(
            attachment: attachment,
            onRemove: () => onRemove(attachment),
          );
        },
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({required this.attachment, required this.onRemove});

  final ChatAttachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filePath = attachment.filePath;
    return ScaleTransition(
      scale: const AlwaysStoppedAnimation<double>(1),
      child: SizedBox(
        width: 104,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: scheme.surfaceContainerHigh),
                  child: _PreviewBody(attachment: attachment),
                ),
              ),
            ),
            if (attachment.isProcessing)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: LinearProgressIndicator(value: attachment.progress),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filled(
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 16),
                tooltip: '削除',
              ),
            ),
            if (filePath != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: Icon(
                  attachment.type == ChatAttachmentType.image
                      ? Icons.image_rounded
                      : Icons.graphic_eq_rounded,
                  color: scheme.onSurface,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.attachment});

  final ChatAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (attachment.type == ChatAttachmentType.image &&
        attachment.filePath != null) {
      return Image.file(File(attachment.filePath!), fit: BoxFit.cover);
    }
    final icon = switch (attachment.type) {
      ChatAttachmentType.audio => Icons.mic_rounded,
      ChatAttachmentType.location => Icons.location_on_rounded,
      ChatAttachmentType.image => Icons.image_rounded,
    };
    return Center(child: Icon(icon, color: scheme.primary, size: 32));
  }
}
