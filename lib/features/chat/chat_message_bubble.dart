import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/web_research_service.dart';
import '../shared/in_app_browser_screen.dart';
import 'audio_message_widget.dart';
import 'chat_controller.dart';
import 'image_message_widget.dart';
import 'location_message_widget.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.message,
    required this.pulse,
    super.key,
  });

  final ChatMessage message;
  final Animation<double> pulse;
  static const MethodChannel _shareChannel = MethodChannel('essential/share');

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    final background = isUser
        ? scheme.primary
        : message.isError
        ? scheme.errorContainer
        : scheme.surfaceContainerHigh;
    final foreground = isUser
        ? scheme.onPrimary
        : message.isError
        ? scheme.onErrorContainer
        : scheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width >= 900 ? 600 : 520,
          ),
          child: AnimatedSlide(
            offset: Offset.zero,
            duration: const Duration(milliseconds: 180),
            child: AnimatedOpacity(
              opacity: 1,
              duration: const Duration(milliseconds: 180),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(24),
                    topRight: const Radius.circular(24),
                    bottomLeft: Radius.circular(isUser ? 24 : 8),
                    bottomRight: Radius.circular(isUser ? 8 : 24),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        isUser ? 'You' : 'Essential',
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (message.attachments.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        for (final attachment
                            in message.attachments) ...<Widget>[
                          _AttachmentBody(
                            attachment: attachment,
                            isUser: isUser,
                          ),
                          const SizedBox(height: 10),
                        ],
                      ],
                      if (message.text.isNotEmpty || message.isStreaming)
                        SelectableText(
                          message.text.isEmpty && message.isStreaming
                              ? '…'
                              : message.text,
                          style: TextStyle(color: foreground, height: 1.45),
                        ),
                      if (!isUser && message.webSources.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 10),
                        _WebSourcesList(
                          sources: message.webSources,
                          foreground: foreground,
                        ),
                      ],
                      if (message.attachments.any((item) => item.isProcessing))
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: foreground,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'AI分析中',
                                style: TextStyle(
                                  color: foreground.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (message.isStreaming) ...<Widget>[
                        const SizedBox(height: 10),
                        FadeTransition(
                          opacity: Tween<double>(
                            begin: 0.35,
                            end: 1,
                          ).animate(pulse),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: foreground,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                message.progressLabel?.trim().isNotEmpty ??
                                        false
                                    ? message.progressLabel!
                                    : '回答生成中',
                                style: TextStyle(
                                  color: foreground.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (!isUser &&
                          !message.isStreaming &&
                          !message.isError &&
                          message.text.trim().isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'LINE・SMS・Gmailなどに共有',
                            onPressed: () async {
                              await _shareChannel.invokeMethod<void>(
                                'sendText',
                                <String, Object?>{
                                  'text': message.text,
                                  'title': '送信先を選択',
                                },
                              );
                            },
                            icon: Icon(
                              Icons.ios_share_rounded,
                              color: foreground.withValues(alpha: 0.82),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WebSourcesList extends StatefulWidget {
  const _WebSourcesList({required this.sources, required this.foreground});

  final List<WebSource> sources;
  final Color foreground;

  @override
  State<_WebSourcesList> createState() => _WebSourcesListState();
}

class _WebSourcesListState extends State<_WebSourcesList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sources = widget.sources;
    final foreground = widget.foreground;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: foreground.withValues(alpha: 0.14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                Icon(
                  Icons.travel_explore_rounded,
                  size: 16,
                  color: foreground.withValues(alpha: 0.82),
                ),
                const SizedBox(width: 6),
                Text(
                  '情報源 ${sources.length}件',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.82),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _expanded ? '閉じる' : '開く',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: foreground.withValues(alpha: 0.76),
                  ),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              for (final source in sources.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: source.url.trim().isEmpty
                        ? null
                        : () => InAppBrowserScreen.open(
                            context,
                            url: source.url,
                            title: source.title,
                          ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _SourceIcon(source: source, foreground: foreground),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  source.title.trim().isEmpty
                                      ? _sourceHost(source.url)
                                      : source.title.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: foreground,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                                if (source.snippet.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      source.snippet.trim(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: foreground.withValues(
                                          alpha: 0.68,
                                        ),
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                  ),
                                if (source.url.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      _sourceHost(source.url),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: foreground.withValues(
                                          alpha: 0.52,
                                        ),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 16,
                            color: foreground.withValues(alpha: 0.58),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SourceIcon extends StatelessWidget {
  const _SourceIcon({required this.source, required this.foreground});

  final WebSource source;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final host = _sourceHost(source.url);
    final letter = host.isEmpty ? 'W' : host.substring(0, 1).toUpperCase();
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: foreground.withValues(alpha: 0.16)),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: foreground.withValues(alpha: 0.86),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _sourceHost(String url) {
  try {
    final host = Uri.parse(url).host;
    if (host.startsWith('www.')) {
      return host.substring(4);
    }
    return host;
  } catch (_) {
    return url;
  }
}

class _AttachmentBody extends StatelessWidget {
  const _AttachmentBody({required this.attachment, required this.isUser});

  final ChatAttachment attachment;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return switch (attachment.type) {
      ChatAttachmentType.image => ImageMessageWidget(
        attachment: attachment,
        isUser: isUser,
      ),
      ChatAttachmentType.audio => AudioMessageWidget(attachment: attachment),
      ChatAttachmentType.location => LocationMessageWidget(
        attachment: attachment,
      ),
    };
  }
}
