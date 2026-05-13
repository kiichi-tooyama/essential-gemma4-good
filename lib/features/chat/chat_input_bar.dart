import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_language.dart';
import 'camera_capture_screen.dart';
import 'chat_controller.dart';
import 'multimodal_composer.dart';
import 'voice_recording_screen.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    required this.controller,
    required this.enabled,
    required this.isGenerating,
    required this.modelLabel,
    required this.adapterLabel,
    required this.hasAvailableModels,
    required this.onChooseModel,
    required this.onChooseAdapter,
    required this.onOpenModels,
    required this.onSendText,
    required this.onSendMultimodal,
    required this.onQuickAction,
    required this.onStop,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isGenerating;
  final String modelLabel;
  final String? adapterLabel;
  final bool hasAvailableModels;
  final VoidCallback onChooseModel;
  final VoidCallback onChooseAdapter;
  final VoidCallback onOpenModels;
  final Future<void> Function() onSendText;
  final Future<void> Function(String text, List<ChatAttachment> attachments)
  onSendMultimodal;
  final Future<void> Function(String prompt) onQuickAction;
  final VoidCallback onStop;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  static const MethodChannel _nativeVoiceChannel = MethodChannel(
    'essential/native_voice',
  );

  final ImagePicker _picker = ImagePicker();
  final List<ChatAttachment> _attachments = <ChatAttachment>[];

  bool get _canSend =>
      widget.enabled &&
      (widget.controller.text.trim().isNotEmpty || _attachments.isNotEmpty);

  List<_QuickAction> get _quickActions {
    final text = widget.controller.text.trim();
    if (text.isEmpty || !widget.enabled || widget.isGenerating) {
      return const <_QuickAction>[];
    }
    final lower = text.toLowerCase();
    final hasUrl = RegExp(r'https?://\S+').hasMatch(text);
    final looksProduct =
        hasUrl ||
        RegExp(
          r'(商品|価格|レビュー|amazon|楽天|型番|品番|購入|買う|比較|どっち|どちら|jan|バーコード)',
        ).hasMatch(lower);
    final looksComparison = RegExp(
      r'(比較|どっち|どちら|vs|対|迷って|おすすめ)',
    ).hasMatch(lower);
    final looksMail = RegExp(
      r'(@|件名|メール|gmail|お世話になっております|返信)',
    ).hasMatch(lower);
    final looksLong = text.runes.length >= 80 || text.contains('\n');
    final actions = <_QuickAction>[
      if (looksLong)
        _QuickAction(
          icon: Icons.summarize_rounded,
          label: context.appText('要約', 'Summarize'),
          prompt: context.appText(
            '次の内容を要点、重要事項、次にやることに分けて日本語で要約して:\n$text',
            'Summarize the following into key points, important details, and next actions in English:\n$text',
          ),
        ),
      if (looksMail)
        _QuickAction(
          icon: Icons.reply_rounded,
          label: context.appText('返信作成', 'Draft reply'),
          prompt: context.appText(
            '次のメール/メッセージへの自然な返信文を作成して。必要なら件名も提案して:\n$text',
            'Draft a natural reply to the following email or message. Suggest a subject if needed:\n$text',
          ),
        ),
      if (hasUrl || looksProduct)
        _QuickAction(
          icon: Icons.reviews_rounded,
          label: context.appText('レビュー要約', 'Review summary'),
          prompt: context.appText(
            '次の商品名・URL・本文をWeb検索し、Amazon等の商品ページやレビュー傾向を確認して、概要、良い点、悪い点、買う前の注意点、確認に使ったURLを日本語でまとめて:\n$text',
            'Search the web for this product name, URL, or text. Summarize product pages and review trends into overview, pros, cons, buying cautions, and source URLs:\n$text',
          ),
        ),
      if (looksProduct)
        _QuickAction(
          icon: Icons.image_search_rounded,
          label: context.appText('商品調査', 'Product research'),
          prompt: context.appText(
            '次の商品名・URL・写真情報から、商品名、型番、JAN/バーコード候補、用途、仕様、レビューで見るべき点、代替候補の探し方をWeb検索込みで整理して:\n$text',
            'Use this product name, URL, or photo context to identify product name, model, JAN/barcode candidates, use cases, specs, review checks, and alternative search terms with web grounding:\n$text',
          ),
        ),
      if (looksProduct || looksComparison)
        _QuickAction(
          icon: Icons.compare_arrows_rounded,
          label: context.appText('比較', 'Compare'),
          prompt: context.appText(
            '次の候補をそれぞれWeb検索し、レビュー傾向、価格帯、仕様、保証、どんな人に向くかで比較し、用途別のおすすめを出して:\n$text',
            'Search each option on the web, compare review trends, price range, specs, warranty, and best-fit users, then recommend by use case:\n$text',
          ),
        ),
      _QuickAction(
        icon: Icons.edit_note_rounded,
        label: context.appText('文章作成', 'Write text'),
        prompt: context.appText(
          '次の内容をもとに、相手に送れる自然な文章を作成して:\n$text',
          'Write a natural message I can send based on the following:\n$text',
        ),
      ),
    ];
    return actions.take(4).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChanged);
      widget.controller.addListener(_handleTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChanged);
    super.dispose();
  }

  void _handleTextChanged() => setState(() {});

  Future<void> _showMediaSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _MediaOption(
                  icon: Icons.photo_camera_rounded,
                  label: context.appText('カメラ', 'Camera'),
                  subtitle: context.appText(
                    '今撮った写真で聞く',
                    'Ask with a new photo',
                  ),
                  onTap: _openCamera,
                ),
                _MediaOption(
                  icon: Icons.photo_library_rounded,
                  label: context.appText('写真', 'Photos'),
                  subtitle: context.appText(
                    'アルバムから選ぶ',
                    'Choose from your library',
                  ),
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                _MediaOption(
                  icon: Icons.mic_rounded,
                  label: context.appText('声で話す', 'Speak'),
                  subtitle: context.appText('音声で質問する', 'Ask by voice'),
                  onTap: _recordVoiceFromSheet,
                ),
                _MediaOption(
                  icon: Icons.record_voice_over_rounded,
                  label: context.appText('会議/通話メモ', 'Meeting/call note'),
                  subtitle: context.appText(
                    '録音を文字起こし・要約・翻訳に使う',
                    'Transcribe, summarize, and translate a recording',
                  ),
                  onTap: _recordLongAudioFromSheet,
                ),
                _MediaOption(
                  icon: Icons.location_on_rounded,
                  label: context.appText('場所', 'Location'),
                  subtitle: context.appText(
                    '今いる場所を添える',
                    'Attach your current location',
                  ),
                  onTap: _addLocation,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCamera() async {
    Navigator.of(context).pop();
    final captured = await Navigator.of(context).push<XFile>(
      MaterialPageRoute<XFile>(builder: (_) => const CameraCaptureScreen()),
    );
    if (captured == null || !mounted) {
      return;
    }
    _addImageAttachment(captured.path);
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.of(context).pop();
    final picked = await _picker.pickImage(source: source, imageQuality: 92);
    if (picked == null || !mounted) {
      return;
    }
    _addImageAttachment(picked.path);
  }

  void _addImageAttachment(String filePath) {
    setState(() {
      _attachments.add(
        ChatAttachment(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: ChatAttachmentType.image,
          filePath: filePath,
          status: ChatAttachmentStatus.processing,
          progress: 0.4,
        ),
      );
    });
  }

  Future<void> _recordVoiceFromSheet() async {
    Navigator.of(context).pop();
    await _startVoiceInput();
  }

  Future<void> _recordLongAudioFromSheet() async {
    Navigator.of(context).pop();
    await _recordAudioAttachment(
      prompt: context.appText(
        'この録音を文字起こしして、要約、決定事項、TODO、重要な発言、必要なら翻訳と返信文案を作成して。',
        'Transcribe this recording, then create a summary, decisions, TODOs, important statements, and translations or reply drafts if needed.',
      ),
      caption: 'Meeting or call recording',
    );
  }

  Future<void> _startVoiceInput() async {
    try {
      final recognized = await _nativeVoiceChannel.invokeMethod<String>(
        'recognizeOnce',
        <String, Object?>{'language': 'ja-JP', 'preferOnDevice': true},
      );
      final text = recognized?.trim();
      if (text != null && text.isNotEmpty && mounted) {
        widget.controller.text = text;
        widget.controller.selection = TextSelection.collapsed(
          offset: widget.controller.text.length,
        );
        await widget.onSendText();
        return;
      }
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.code == 'microphone_permission'
          ? context.appText(
              'マイク権限を許可してからもう一度話してください。',
              'Allow microphone access, then try speaking again.',
            )
          : error.code == 'speech_unavailable'
          ? context.appText(
              'この端末では端末内音声認識を利用できません。',
              'On-device speech recognition is not available on this device.',
            )
          : context.appText(
              '音声を聞き取れませんでした。もう一度話してください。',
              'I could not hear the audio. Please try speaking again.',
            );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    } catch (_) {
      // Voice input uses Android's on-device SpeechRecognizer.
      return;
    }
  }

  Future<void> _recordAudioAttachment({
    String? prompt,
    required String caption,
  }) async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const VoiceRecordingScreen()),
    );
    if (path == null || !mounted) {
      return;
    }
    if (prompt != null && prompt.trim().isNotEmpty) {
      widget.controller.text = prompt.trim();
      widget.controller.selection = TextSelection.collapsed(
        offset: widget.controller.text.length,
      );
    }
    setState(() {
      _attachments.add(
        ChatAttachment(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: ChatAttachmentType.audio,
          filePath: path,
          caption: caption,
          status: ChatAttachmentStatus.processing,
          progress: 0.4,
        ),
      );
    });
  }

  Future<void> _addLocation() async {
    Navigator.of(context).pop();
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.appText(
                '位置情報の権限がありません。',
                'Location permission is not available.',
              ),
            ),
          ),
        );
      }
      return;
    }
    final position = await Geolocator.getCurrentPosition();
    if (!mounted) {
      return;
    }
    setState(() {
      _attachments.add(
        ChatAttachment(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          type: ChatAttachmentType.location,
          location: LocationData(
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
          ),
        ),
      );
    });
  }

  Future<void> _send() async {
    if (!_canSend) {
      return;
    }
    if (_attachments.isEmpty) {
      await widget.onSendText();
      return;
    }
    final attachments = List<ChatAttachment>.from(_attachments);
    final text = widget.controller.text.trim();
    widget.controller.clear();
    setState(_attachments.clear);
    await widget.onSendMultimodal(text, attachments);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(26),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _InputModelControls(
              modelLabel: widget.modelLabel,
              adapterLabel: widget.adapterLabel,
              hasAvailableModels: widget.hasAvailableModels,
              enabled: widget.enabled && !widget.isGenerating,
              onChooseModel: widget.onChooseModel,
              onChooseAdapter: widget.onChooseAdapter,
              onOpenModels: widget.onOpenModels,
            ),
            const SizedBox(height: 8),
            if (_attachments.isNotEmpty)
              MultimodalComposer(
                attachments: _attachments,
                onRemove: (attachment) {
                  setState(() => _attachments.remove(attachment));
                },
              ),
            if (_quickActions.isNotEmpty) ...<Widget>[
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _quickActions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final action = _quickActions[index];
                    return ActionChip(
                      avatar: Icon(action.icon, size: 18),
                      label: Text(action.label),
                      onPressed: () => widget.onQuickAction(action.prompt),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                IconButton.filledTonal(
                  constraints: const BoxConstraints.tightFor(
                    width: 38,
                    height: 38,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: widget.enabled && !widget.isGenerating
                      ? _showMediaSheet
                      : null,
                  icon: const Icon(Icons.add_rounded, size: 22),
                  tooltip: context.appText('写真や音声を追加', 'Add photos or audio'),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 5,
                    enabled: widget.enabled && !widget.isGenerating,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: context.appText('メッセージを入力', 'Type a message'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: widget.isGenerating
                      ? IconButton.filledTonal(
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 38,
                          ),
                          padding: EdgeInsets.zero,
                          key: const ValueKey<String>('stop'),
                          onPressed: widget.onStop,
                          icon: const Icon(Icons.stop_rounded, size: 22),
                          tooltip: context.appText('停止', 'Stop'),
                        )
                      : IconButton.filled(
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 38,
                          ),
                          padding: EdgeInsets.zero,
                          key: const ValueKey<String>('send'),
                          onPressed: _canSend ? _send : null,
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 22,
                          ),
                          tooltip: context.appText('送信', 'Send'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.prompt,
  });

  final IconData icon;
  final String label;
  final String prompt;
}

class _InputModelControls extends StatelessWidget {
  const _InputModelControls({
    required this.modelLabel,
    required this.adapterLabel,
    required this.hasAvailableModels,
    required this.enabled,
    required this.onChooseModel,
    required this.onChooseAdapter,
    required this.onOpenModels,
  });

  final String modelLabel;
  final String? adapterLabel;
  final bool hasAvailableModels;
  final bool enabled;
  final VoidCallback onChooseModel;
  final VoidCallback onChooseAdapter;
  final VoidCallback onOpenModels;

  @override
  Widget build(BuildContext context) {
    return _InputControlButton(
      icon: Icons.auto_awesome_rounded,
      label: hasAvailableModels ? modelLabel : 'AIを追加',
      onPressed: enabled
          ? hasAvailableModels
                ? onChooseModel
                : onOpenModels
          : null,
    );
  }
}

class _InputControlButton extends StatelessWidget {
  const _InputControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _MediaOption extends StatelessWidget {
  const _MediaOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
