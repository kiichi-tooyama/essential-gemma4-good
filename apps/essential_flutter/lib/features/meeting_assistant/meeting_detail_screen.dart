import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/app_language.dart';
import '../shared/in_app_browser_screen.dart';
import '../shared/web_research_service.dart';
import 'meeting_controller.dart';
import 'meeting_enhancements.dart';
import 'meeting_models.dart';

class MeetingDetailScreen extends StatefulWidget {
  const MeetingDetailScreen({
    required this.session,
    required this.controller,
    super.key,
  });

  final MeetingSession session;
  final MeetingController controller;

  @override
  State<MeetingDetailScreen> createState() => _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends State<MeetingDetailScreen> {
  static const MethodChannel _voiceChannel = MethodChannel(
    'essential/native_voice',
  );
  final ValueNotifier<Duration?> _seekRequest = ValueNotifier<Duration?>(null);
  final ValueNotifier<Duration> _playbackPosition = ValueNotifier<Duration>(
    Duration.zero,
  );
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _seekRequest.dispose();
    _playbackPosition.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final currentSession = widget.controller.sessions.firstWhere(
          (s) => s.id == widget.session.id,
          orElse: () => widget.session,
        );
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(currentSession.title),
              centerTitle: true,
              bottom: currentSession.status == MeetingStatus.completed
                  ? TabBar(
                      tabs: <Widget>[
                        Tab(
                          text: widget.controller.strings.t(
                            'meeting.sourceTab',
                          ),
                        ),
                        Tab(
                          text: widget.controller.strings.t('meeting.notesTab'),
                        ),
                      ],
                    )
                  : null,
              actions: [
                IconButton(
                  tooltip: widget.controller.strings.t(
                    'meeting.shareMarkdownTooltip',
                  ),
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: currentSession.status == MeetingStatus.completed
                      ? () => widget.controller.shareMeetingMarkdown(
                          currentSession,
                        )
                      : null,
                ),
              ],
            ),
            body: currentSession.status == MeetingStatus.processing
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          currentSession.processingStage.trim().isEmpty
                              ? widget.controller.strings.t(
                                  'meeting.processing',
                                )
                              : currentSession.processingStage,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currentSession.processingDetail.trim().isEmpty
                              ? widget.controller.strings.t(
                                  'meeting.processingDetail',
                                )
                              : currentSession.processingDetail,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : TabBarView(
                    children: <Widget>[
                      _buildSourceTab(currentSession),
                      _buildNoteTab(currentSession),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSourceTab(MeetingSession currentSession) {
    final searchResults = _searchQuery.trim().isEmpty
        ? const <MeetingSearchResult>[]
        : MeetingTextProcessor.search(<MeetingSession>[
            currentSession,
          ], _searchQuery);
    return CustomScrollView(
      slivers: <Widget>[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: _AudioPanel(
              session: currentSession,
              controller: widget.controller,
              seekRequest: _seekRequest,
              playbackPosition: _playbackPosition,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
          sliver: SliverToBoxAdapter(
            child: _SearchPanel(
              controller: _searchController,
              strings: widget.controller.strings,
              query: _searchQuery,
              results: searchResults,
              onChanged: (value) => setState(() => _searchQuery = value),
              onSeek: _seekToSeconds,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          sliver: SliverToBoxAdapter(
            child: _TopicTimeline(
              session: currentSession,
              controller: widget.controller,
              onSeek: _seekToSeconds,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          sliver: SliverToBoxAdapter(
            child: _UnknownSpeakerPrompt(
              session: currentSession,
              controller: widget.controller,
              onSeek: _seekToSeconds,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        _TranscriptSection(
          session: currentSession,
          controller: widget.controller,
          playbackPosition: _playbackPosition,
          onSeek: _seekToSeconds,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildNoteTab(MeetingSession currentSession) {
    final templateText =
        currentSession.templateOutputs[currentSession.templateId] ??
        currentSession.summary;
    final summaryText = currentSession.summary.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        _TemplateChooser(
          session: currentSession,
          controller: widget.controller,
        ),
        const SizedBox(height: 12),
        _Keywords(session: currentSession),
        const SizedBox(height: 18),
        _SummarySection(
          title: widget.controller.strings.t('meeting.summary'),
          text: summaryText.isEmpty
              ? widget.controller.strings.t('meeting.noSummary')
              : _cleanDisplayText(summaryText),
          onSpeak: () => _speakSummary(summaryText),
          onStop: _stopSummarySpeech,
        ),
        const SizedBox(height: 20),
        _SentimentPanel(session: currentSession),
        const SizedBox(height: 20),
        _NoteSets(session: currentSession),
        const SizedBox(height: 20),
        _TodoSection(session: currentSession, controller: widget.controller),
        const SizedBox(height: 20),
        _Bookmarks(session: currentSession, onSeek: _seekToSeconds),
        const SizedBox(height: 20),
        _AskSuggestions(session: currentSession, controller: widget.controller),
        const SizedBox(height: 20),
        _MindMap(nodes: currentSession.mindMap, onSeek: _seekToSeconds),
        const SizedBox(height: 20),
        _Translations(
          session: currentSession,
          controller: widget.controller,
          summaryText: templateText,
        ),
        const SizedBox(height: 20),
        _WebSources(
          sources: currentSession.webSources,
          controller: widget.controller,
        ),
        const SizedBox(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(widget.controller.strings.t('meeting.sharedMemory')),
          value: currentSession.sharedMemoryEnabled,
          onChanged: (value) => widget.controller.setSharedMemoryEnabled(
            currentSession.id,
            value,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _openChat(context, currentSession),
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(widget.controller.strings.t('meeting.askAi')),
        ),
      ],
    );
  }

  void _seekToSeconds(double seconds) {
    _seekRequest.value = Duration(milliseconds: (seconds * 1000).round());
  }

  void _openChat(BuildContext context, MeetingSession session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _MeetingChatView(
            session: session,
            controller: widget.controller,
          ),
        );
      },
    );
  }

  Future<void> _speakSummary(String text) async {
    final normalized = _cleanSpeechTextForTts(_cleanDisplayText(text)).trim();
    if (normalized.isEmpty) {
      return;
    }
    try {
      await _voiceChannel.invokeMethod<void>('speak', <String, Object?>{
        'text': normalized,
        'language': widget.controller.useEnglish ? 'en-US' : 'ja-JP',
      });
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? '読み上げを開始できませんでした')),
      );
    }
  }

  Future<void> _stopSummarySpeech() async {
    try {
      await _voiceChannel.invokeMethod<void>('stopSpeaking');
    } on PlatformException {
      // Stop is best-effort; native TTS may not be initialized yet.
    }
  }
}

class _AudioPanel extends StatefulWidget {
  const _AudioPanel({
    required this.session,
    required this.controller,
    required this.seekRequest,
    required this.playbackPosition,
  });

  final MeetingSession session;
  final MeetingController controller;
  final ValueNotifier<Duration?> seekRequest;
  final ValueNotifier<Duration> playbackPosition;

  @override
  State<_AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends State<_AudioPanel> {
  late final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    widget.seekRequest.addListener(_handleSeekRequest);
    _load();
  }

  @override
  void didUpdateWidget(_AudioPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seekRequest != widget.seekRequest) {
      oldWidget.seekRequest.removeListener(_handleSeekRequest);
      widget.seekRequest.addListener(_handleSeekRequest);
    }
    if (oldWidget.session.audioPath != widget.session.audioPath) {
      _ready = false;
      _error = '';
      _load();
    }
  }

  Future<void> _load() async {
    try {
      await _player.setFilePath(widget.session.audioPath);
      if (mounted) {
        setState(() => _ready = true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  @override
  void dispose() {
    widget.seekRequest.removeListener(_handleSeekRequest);
    _player.dispose();
    super.dispose();
  }

  Future<void> _handleSeekRequest() async {
    final request = widget.seekRequest.value;
    if (request == null || !_ready) {
      return;
    }
    await _player.seek(request);
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 4,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    return IconButton.filled(
                      tooltip: playing
                          ? context.appText('一時停止', 'Pause')
                          : context.appText('再生', 'Play'),
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: !_ready
                          ? null
                          : () => playing ? _player.pause() : _player.play(),
                    );
                  },
                ),
                IconButton(
                  tooltip: context.appText('15秒戻る', 'Back 15 seconds'),
                  icon: const Icon(Icons.replay_10_rounded),
                  onPressed: !_ready
                      ? null
                      : () => _seekRelative(const Duration(seconds: -15)),
                ),
                IconButton(
                  tooltip: context.appText('15秒進む', 'Forward 15 seconds'),
                  icon: const Icon(Icons.forward_10_rounded),
                  onPressed: !_ready
                      ? null
                      : () => _seekRelative(const Duration(seconds: 15)),
                ),
                PopupMenuButton<double>(
                  tooltip: context.appText('再生速度', 'Playback speed'),
                  icon: const Icon(Icons.speed_rounded),
                  onSelected: (speed) {
                    _player.setSpeed(speed);
                    widget.controller.setAudioOptions(
                      widget.session.id,
                      widget.session.audioOptions.copyWith(
                        playbackSpeed: speed,
                      ),
                    );
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 0.5, child: Text('0.5x')),
                    PopupMenuItem(value: 0.75, child: Text('0.75x')),
                    PopupMenuItem(value: 1.0, child: Text('1.0x')),
                    PopupMenuItem(value: 1.25, child: Text('1.25x')),
                    PopupMenuItem(value: 1.5, child: Text('1.5x')),
                    PopupMenuItem(value: 1.75, child: Text('1.75x')),
                    PopupMenuItem(value: 2.0, child: Text('2.0x')),
                  ],
                ),
                IconButton(
                  tooltip: widget.session.audioOptions.voiceEnhancementEnabled
                      ? context.appText('AI音声補正オン', 'AI voice enhancement on')
                      : context.appText('AI音声補正オフ', 'AI voice enhancement off'),
                  icon: Icon(
                    widget.session.audioOptions.voiceEnhancementEnabled
                        ? Icons.auto_fix_high_rounded
                        : Icons.auto_fix_off_rounded,
                  ),
                  onPressed: () => widget.controller.setAudioOptions(
                    widget.session.id,
                    widget.session.audioOptions.copyWith(
                      voiceEnhancementEnabled:
                          !widget.session.audioOptions.voiceEnhancementEnabled,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: widget.session.audioOptions.silenceSkipEnabled
                      ? context.appText('無音スキップオン', 'Silence skip on')
                      : context.appText('無音スキップオフ', 'Silence skip off'),
                  icon: Icon(
                    widget.session.audioOptions.silenceSkipEnabled
                        ? Icons.skip_next_rounded
                        : Icons.skip_next_outlined,
                  ),
                  onPressed: () => widget.controller.setAudioOptions(
                    widget.session.id,
                    widget.session.audioOptions.copyWith(
                      silenceSkipEnabled:
                          !widget.session.audioOptions.silenceSkipEnabled,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.appText(
                    '現在位置を重要マーク',
                    'Bookmark current position',
                  ),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: !_ready
                      ? null
                      : () => widget.controller.addBookmark(
                          widget.session.id,
                          _player.position.inMilliseconds / 1000,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    _formatDuration(
                      Duration(seconds: widget.session.durationSeconds),
                    ),
                  ),
                ),
              ],
            ),
            StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                widget.playbackPosition.value = position;
                final duration =
                    _player.duration ??
                    Duration(seconds: widget.session.durationSeconds);
                return Column(
                  children: [
                    Slider(
                      value: position.inMilliseconds
                          .clamp(0, duration.inMilliseconds)
                          .toDouble(),
                      max: duration.inMilliseconds <= 0
                          ? 1
                          : duration.inMilliseconds.toDouble(),
                      onChanged: !_ready
                          ? null
                          : (value) => _player.seek(
                              Duration(milliseconds: value.round()),
                            ),
                    ),
                    Row(
                      children: [
                        Text(_formatDuration(position)),
                        const Spacer(),
                        Text(_formatDuration(duration)),
                      ],
                    ),
                  ],
                );
              },
            ),
            if (_error.isNotEmpty)
              Text(
                'Could not load audio: $_error',
                style: TextStyle(color: colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _seekRelative(Duration delta) async {
    final next = _player.position + delta;
    await _player.seek(next < Duration.zero ? Duration.zero : next);
  }
}

class _TopicTimeline extends StatelessWidget {
  const _TopicTimeline({
    required this.session,
    required this.controller,
    this.onSeek,
  });

  final MeetingSession session;
  final MeetingController controller;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    if (session.topicSegments.isEmpty) {
      return _Section(
        title: controller.strings.t('meeting.timelineTitle'),
        text: controller.strings.t('meeting.noTimeline'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, controller.strings.t('meeting.timelineTitle')),
        for (final topic in session.topicSegments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(_formatSeconds(topic.startSeconds)),
            title: Text(topic.title),
            subtitle: topic.summary.trim().isEmpty ? null : Text(topic.summary),
            onTap: onSeek == null ? null : () => onSeek!(topic.startSeconds),
          ),
      ],
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.controller,
    required this.strings,
    required this.query,
    required this.results,
    required this.onChanged,
    required this.onSeek,
  });

  final TextEditingController controller;
  final AppLanguagePack strings;
  final String query;
  final List<MeetingSearchResult> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: strings.t('meeting.searchInRecording'),
            border: OutlineInputBorder(),
          ),
        ),
        if (query.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          if (results.isEmpty)
            Text(
              strings.t('meeting.searchNoUtterance'),
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final result in results.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text(_formatSeconds(result.startSeconds)),
                title: Text(result.snippet),
                subtitle: Text(result.source),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () => onSeek(result.startSeconds),
              ),
        ],
      ],
    );
  }
}

class _TemplateChooser extends StatelessWidget {
  const _TemplateChooser({required this.session, required this.controller});

  final MeetingSession session;
  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    final selected = MeetingTextProcessor.templateById(session.templateId);
    return Row(
      children: <Widget>[
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: selected.id,
            decoration: InputDecoration(
              labelText: controller.strings.t('meeting.templateLabel'),
              border: OutlineInputBorder(),
            ),
            items: [
              for (final template in MeetingTextProcessor.templates)
                DropdownMenuItem<String>(
                  value: template.id,
                  child: Text(
                    _localizedTemplateTitle(
                      template.id,
                      template.title,
                      context,
                    ),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.setSessionTemplate(session.id, value);
              }
            },
          ),
        ),
        const SizedBox(width: 10),
        Text(
          context.appText(
            '${MeetingTextProcessor.templates.length}種',
            '${MeetingTextProcessor.templates.length} types',
          ),
        ),
      ],
    );
  }
}

class _Keywords extends StatelessWidget {
  const _Keywords({required this.session});

  final MeetingSession session;

  @override
  Widget build(BuildContext context) {
    if (session.keywords.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, context.appText('キーワード', 'Keywords')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final keyword in session.keywords)
              Chip(label: Text(keyword), visualDensity: VisualDensity.compact),
          ],
        ),
      ],
    );
  }
}

class _SentimentPanel extends StatelessWidget {
  const _SentimentPanel({required this.session});

  final MeetingSession session;

  @override
  Widget build(BuildContext context) {
    final sentiment = session.sentiment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, context.appText('感情分析', 'Sentiment')),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: <Widget>[
                _MetricBar(
                  label: context.appText('満足度', 'Satisfaction'),
                  value: sentiment.satisfaction,
                ),
                _MetricBar(
                  label: context.appText('モチベーション', 'Motivation'),
                  value: sentiment.motivation,
                ),
                _MetricBar(
                  label: context.appText('懸念', 'Concern'),
                  value: sentiment.concern,
                ),
                const SizedBox(height: 8),
                Text(
                  _localizedSentimentSummary(sentiment, context),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricBar extends StatelessWidget {
  const _MetricBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          SizedBox(width: 104, child: Text(label)),
          Expanded(
            child: LinearProgressIndicator(value: value.clamp(0, 1).toDouble()),
          ),
          const SizedBox(width: 10),
          Text('${(value.clamp(0, 1) * 100).round()}%'),
        ],
      ),
    );
  }
}

class _Bookmarks extends StatelessWidget {
  const _Bookmarks({required this.session, required this.onSeek});

  final MeetingSession session;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    if (session.bookmarks.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _sectionTitle(context, context.appText('重要マーク', 'Bookmarks')),
        for (final bookmark in session.bookmarks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bookmark_rounded),
            title: Text(bookmark.label),
            subtitle: bookmark.note.trim().isEmpty
                ? Text(_formatSeconds(bookmark.startSeconds))
                : Text(bookmark.note),
            trailing: const Icon(Icons.play_arrow_rounded),
            onTap: () => onSeek(bookmark.startSeconds),
          ),
      ],
    );
  }
}

class _NoteSets extends StatefulWidget {
  const _NoteSets({required this.session});

  final MeetingSession session;

  @override
  State<_NoteSets> createState() => _NoteSetsState();
}

class _NoteSetsState extends State<_NoteSets> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(covariant _NoteSets oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.session.noteSets.length) {
      _selectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.session.noteSets.isEmpty) {
      return const SizedBox.shrink();
    }
    final selected = widget.session.noteSets[_selectedIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, context.appText('ノート', 'Notes')),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < widget.session.noteSets.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      _localizedMeetingLabel(
                        widget.session.noteSets[i].title,
                        context,
                      ),
                    ),
                    selected: i == _selectedIndex,
                    onSelected: (_) => setState(() => _selectedIndex = i),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              _cleanDisplayText(_localizedMeetingText(selected.body, context)),
            ),
          ),
        ),
      ],
    );
  }
}

class _AskSuggestions extends StatelessWidget {
  const _AskSuggestions({required this.session, required this.controller});

  final MeetingSession session;
  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    if (session.askSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, context.appText('AIに聞けること', 'Ask AI')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final question in session.askSuggestions)
              ActionChip(
                avatar: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(question),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (context) => Padding(
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: _MeetingChatView(
                      session: session,
                      controller: controller,
                      initialQuestion: question,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MindMap extends StatelessWidget {
  const _MindMap({required this.nodes, this.onSeek});

  final List<MeetingMindMapNode> nodes;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionTitle(
                context,
                context.appText('マインドマップ', 'Mind map'),
              ),
            ),
            IconButton(
              tooltip: context.appText('全画面', 'Full screen'),
              icon: const Icon(Icons.open_in_full_rounded),
              onPressed: () => _openFullScreen(context),
            ),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 420,
              child: _MindMapCanvas(nodes: nodes, onSeek: onSeek),
            ),
          ),
        ),
      ],
    );
  }

  void _openFullScreen(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: context.appText('閉じる', 'Close'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: _MindMapCanvas(
                  nodes: nodes,
                  onSeek: onSeek,
                  initialFit: _MindMapInitialFit.overview,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MindMapCanvas extends StatefulWidget {
  const _MindMapCanvas({
    required this.nodes,
    this.onSeek,
    this.initialFit = _MindMapInitialFit.readable,
  });

  final List<MeetingMindMapNode> nodes;
  final ValueChanged<double>? onSeek;
  final _MindMapInitialFit initialFit;

  @override
  State<_MindMapCanvas> createState() => _MindMapCanvasState();
}

class _MindMapCanvasState extends State<_MindMapCanvas> {
  final TransformationController _transform = TransformationController();
  final Map<int, Offset> _activePointers = <int, Offset>{};
  Size? _lastLayoutSize;
  Size? _lastViewportSize;
  Offset? _lastFocalPoint;
  double? _lastPointerDistance;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final root = widget.nodes.isEmpty
        ? MeetingMindMapNode(label: context.appText('会議', 'Meeting'))
        : widget.nodes.first;
    final displayRoot = _mindMapDisplayRoot(root, context);
    final layout = _MindMapLayout.build(displayRoot, <MeetingMindMapNode>[
      displayRoot,
    ]);
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : layout.size.width,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : layout.size.height,
        );
        _scheduleFitIfNeeded(layout.size, viewportSize, layout.nodes);
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: RawGestureDetector(
                gestures: <Type, GestureRecognizerFactory>{
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        EagerGestureRecognizer
                      >(() => EagerGestureRecognizer(), (_) {}),
                },
                behavior: HitTestBehavior.opaque,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _handlePointerDown,
                  onPointerMove: _handlePointerMove,
                  onPointerUp: _handlePointerEnd,
                  onPointerCancel: _handlePointerEnd,
                  child: ClipRect(
                    child: AnimatedBuilder(
                      animation: _transform,
                      builder: (context, child) {
                        return OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: layout.size.width,
                          maxWidth: layout.size.width,
                          minHeight: layout.size.height,
                          maxHeight: layout.size.height,
                          child: Transform(
                            transform: _transform.value,
                            alignment: Alignment.topLeft,
                            child: child,
                          ),
                        );
                      },
                      child: SizedBox(
                        width: layout.size.width,
                        height: layout.size.height,
                        child: CustomPaint(
                          painter: _MindMapPainter(layout.edges),
                          child: Stack(
                            children: [
                              for (final node in layout.nodes)
                                _nodeChip(
                                  node.node,
                                  node.offset,
                                  node.depth == 0,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: context.appText('縮小', 'Zoom out'),
                      icon: const Icon(Icons.remove_rounded),
                      onPressed: () => _scale(0.82),
                    ),
                    IconButton(
                      tooltip: context.appText('画面に合わせる', 'Fit to screen'),
                      icon: const Icon(Icons.fit_screen_rounded),
                      onPressed: () =>
                          _resetView(layout.size, viewportSize, layout.nodes),
                    ),
                    IconButton(
                      tooltip: context.appText('拡大', 'Zoom in'),
                      icon: const Icon(Icons.add_rounded),
                      onPressed: () => _scale(1.18),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  MeetingMindMapNode _mindMapDisplayRoot(
    MeetingMindMapNode root,
    BuildContext context,
  ) {
    MeetingMindMapNode normalize(MeetingMindMapNode node, int depth) {
      if (depth >= 2) {
        final label = _joinedMindMapLabel(node, context);
        return MeetingMindMapNode(
          id: node.id,
          label: label,
          summary: node.summary,
          startSeconds: node.startSeconds,
        );
      }
      final children = node.children
          .map((child) => normalize(child, depth + 1))
          .where((child) => _mindMapNodeLabel(child, context).trim().isNotEmpty)
          .toList(growable: false);
      return MeetingMindMapNode(
        id: node.id,
        label: node.label,
        summary: node.summary,
        startSeconds: node.startSeconds,
        children: children,
      );
    }

    return normalize(root, 0);
  }

  String _joinedMindMapLabel(MeetingMindMapNode node, BuildContext context) {
    final parts = <String>[];
    void collect(MeetingMindMapNode current) {
      final label = _mindMapNodeLabel(current, context).trim();
      if (label.isNotEmpty && !parts.contains(label)) {
        parts.add(label);
      }
      for (final child in current.children) {
        collect(child);
      }
    }

    collect(node);
    if (parts.isEmpty) {
      return context.appText('項目', 'Item');
    }
    return _takeTextRunes(parts.join(' / '), 72);
  }

  Widget _nodeChip(MeetingMindMapNode node, Offset offset, bool primary) {
    final colorScheme = Theme.of(context).colorScheme;
    final nodeSize = _MindMapLayout.nodeSizeForDepth(primary ? 0 : 1);
    final background = primary ? colorScheme.primaryContainer : Colors.white;
    final foreground = primary
        ? colorScheme.onPrimaryContainer
        : const Color(0xFF202126);
    final label = _mindMapNodeLabel(node, context);
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSeek?.call(node.startSeconds),
        child: Material(
          color: background,
          elevation: primary ? 3 : 2,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
          surfaceTintColor: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: primary
                    ? colorScheme.primary.withValues(alpha: 0.55)
                    : const Color(0xFFE0E2E8),
                width: primary ? 1.4 : 1.0,
              ),
            ),
            child: SizedBox(
              width: nodeSize.width,
              height: nodeSize.height,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Center(
                  child: Text(
                    label,
                    maxLines: primary ? 3 : 4,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: primary ? 13 : 12,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _scale(double factor) {
    final viewportSize = _lastViewportSize;
    _applyScale(
      factor,
      viewportSize == null
          ? Offset.zero
          : Offset(viewportSize.width / 2, viewportSize.height / 2),
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    _resetPointerGestureBaseline();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final previousPosition = _activePointers[event.pointer];
    if (previousPosition == null) {
      return;
    }
    _activePointers[event.pointer] = event.localPosition;
    if (_activePointers.length == 1) {
      _translate(event.localPosition - previousPosition);
      return;
    }
    final positions = _activePointers.values.take(2).toList(growable: false);
    final focalPoint = Offset(
      (positions[0].dx + positions[1].dx) / 2,
      (positions[0].dy + positions[1].dy) / 2,
    );
    final distance = (positions[0] - positions[1]).distance;
    final lastFocal = _lastFocalPoint;
    final lastDistance = _lastPointerDistance;
    if (lastFocal != null) {
      _translate(focalPoint - lastFocal);
    }
    if (lastDistance != null && lastDistance > 0 && distance > 0) {
      _applyScale(distance / lastDistance, focalPoint);
    }
    _lastFocalPoint = focalPoint;
    _lastPointerDistance = distance;
  }

  void _handlePointerEnd(PointerEvent event) {
    _activePointers.remove(event.pointer);
    _resetPointerGestureBaseline();
  }

  void _resetPointerGestureBaseline() {
    if (_activePointers.length < 2) {
      _lastFocalPoint = null;
      _lastPointerDistance = null;
      return;
    }
    final positions = _activePointers.values.take(2).toList(growable: false);
    _lastFocalPoint = Offset(
      (positions[0].dx + positions[1].dx) / 2,
      (positions[0].dy + positions[1].dy) / 2,
    );
    _lastPointerDistance = (positions[0] - positions[1]).distance;
  }

  void _translate(Offset delta) {
    final matrix = Matrix4.copy(_transform.value);
    matrix.storage[12] += delta.dx;
    matrix.storage[13] += delta.dy;
    _transform.value = matrix;
  }

  void _applyScale(double factor, Offset focalPoint) {
    final currentScale = _transform.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor)
        .clamp(_minimumScale(), 4.0)
        .toDouble();
    final effectiveFactor = targetScale / currentScale;
    if (!effectiveFactor.isFinite || (effectiveFactor - 1).abs() < 0.001) {
      return;
    }
    _transform.value = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(effectiveFactor, effectiveFactor, 1, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1)
      ..multiply(_transform.value);
  }

  double _minimumScale() {
    return widget.initialFit == _MindMapInitialFit.overview ? 0.44 : 0.58;
  }

  void _scheduleFitIfNeeded(
    Size layoutSize,
    Size viewportSize,
    List<_MindMapLayoutNode> nodes,
  ) {
    if (_lastLayoutSize == layoutSize && _lastViewportSize == viewportSize) {
      return;
    }
    _lastLayoutSize = layoutSize;
    _lastViewportSize = viewportSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (widget.initialFit == _MindMapInitialFit.overview) {
          _fitToView(layoutSize, viewportSize);
        } else {
          _fitReadable(layoutSize, viewportSize, nodes);
        }
      }
    });
  }

  void _resetView(
    Size layoutSize,
    Size viewportSize,
    List<_MindMapLayoutNode> nodes,
  ) {
    if (widget.initialFit == _MindMapInitialFit.overview) {
      _fitToView(layoutSize, viewportSize);
    } else {
      _fitReadable(layoutSize, viewportSize, nodes);
    }
  }

  void _fitToView(Size layoutSize, Size viewportSize) {
    final fitScale = math.min(
      viewportSize.width / (layoutSize.width + 48),
      viewportSize.height / (layoutSize.height + 48),
    );
    final scale = fitScale.clamp(_minimumScale(), 1.2).toDouble();
    final dx = (viewportSize.width - layoutSize.width * scale) / 2;
    final dy = (viewportSize.height - layoutSize.height * scale) / 2;
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _fitReadable(
    Size layoutSize,
    Size viewportSize,
    List<_MindMapLayoutNode> nodes,
  ) {
    final visibleRightEdge = nodes
        .where((node) => node.depth <= 1)
        .map(
          (node) =>
              node.offset.dx +
              _MindMapLayout.nodeSizeForDepth(node.depth).width,
        )
        .fold<double>(0, math.max);
    final readableWidth = math.max(visibleRightEdge + 32, 420);
    final scale = (math.min(
      viewportSize.width / readableWidth,
      viewportSize.height / math.min(layoutSize.height + 32, 620),
    )).clamp(0.92, 1.18);
    _MindMapLayoutNode? root;
    for (final node in nodes) {
      if (node.depth == 0) {
        root = node;
        break;
      }
    }
    final focus = root?.offset ?? const Offset(88, 84);
    final dx = math.max(12.0, 18 - focus.dx * scale);
    final dy = math.max(18.0, viewportSize.height * 0.22 - focus.dy * scale);
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }
}

enum _MindMapInitialFit { readable, overview }

class _MindMapPainter extends CustomPainter {
  const _MindMapPainter(this.edges);

  final List<_MindMapEdge> edges;

  @override
  void paint(Canvas canvas, Size size) {
    final colors = <Color>[
      const Color(0xFFD9B58C),
      const Color(0xFFD8D88A),
      const Color(0xFFA8D77D),
      const Color(0xFF7DD5AC),
      const Color(0xFF77C7D9),
      const Color(0xFFA897D9),
    ];
    for (var i = 0; i < edges.length; i++) {
      final edge = edges[i];
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..strokeWidth = edge.depth <= 1 ? 3 : 1.8
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(edge.from.dx, edge.from.dy)
        ..cubicTo(
          edge.from.dx + 70,
          edge.from.dy,
          edge.to.dx - 70,
          edge.to.dy,
          edge.to.dx,
          edge.to.dy,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapPainter oldDelegate) {
    return oldDelegate.edges != edges;
  }
}

class _MindMapLayout {
  const _MindMapLayout({
    required this.nodes,
    required this.edges,
    required this.size,
  });

  final List<_MindMapLayoutNode> nodes;
  final List<_MindMapEdge> edges;
  final Size size;

  static _MindMapLayout build(
    MeetingMindMapNode root,
    List<MeetingMindMapNode> originalNodes,
  ) {
    final topChildren = root.children.isEmpty && originalNodes.length > 1
        ? originalNodes.skip(1).toList(growable: false)
        : root.children;
    final effectiveRoot = topChildren.isEmpty
        ? root
        : MeetingMindMapNode(
            id: root.id,
            label: root.label,
            summary: root.summary,
            startSeconds: root.startSeconds,
            children: topChildren,
          );
    final maxDepth = _maxDepth(effectiveRoot);
    final nodes = <_MindMapLayoutNode>[];
    final edges = <_MindMapEdge>[];
    var cursor = 84.0;

    Offset place(MeetingMindMapNode node, int depth, Offset? parent) {
      final children = node.children;
      final nodeSize = nodeSizeForDepth(depth);
      final x = 44.0 + depth * 230;
      late final double y;
      if (children.isEmpty) {
        y = cursor;
        cursor += nodeSize.height + 42;
      } else {
        final childOffsets = <Offset>[];
        for (final child in children) {
          childOffsets.add(place(child, depth + 1, null));
        }
        y = (childOffsets.first.dy + childOffsets.last.dy) / 2;
      }
      final offset = Offset(x, y);
      nodes.add(_MindMapLayoutNode(node: node, offset: offset, depth: depth));
      if (parent != null) {
        final parentSize = nodeSizeForDepth(depth - 1);
        edges.add(
          _MindMapEdge(
            from: Offset(
              parent.dx + parentSize.width,
              parent.dy + parentSize.height / 2,
            ),
            to: Offset(offset.dx, offset.dy + nodeSize.height / 2),
            depth: depth,
          ),
        );
      }
      for (final child in children) {
        final childNode = nodes.firstWhere(
          (layoutNode) => identical(layoutNode.node, child),
        );
        final childSize = nodeSizeForDepth(childNode.depth);
        edges.add(
          _MindMapEdge(
            from: Offset(
              offset.dx + nodeSize.width,
              offset.dy + nodeSize.height / 2,
            ),
            to: Offset(
              childNode.offset.dx,
              childNode.offset.dy + childSize.height / 2,
            ),
            depth: depth + 1,
          ),
        );
      }
      return offset;
    }

    place(effectiveRoot, 0, null);
    final rightEdge = nodes
        .map((node) => node.offset.dx + nodeSizeForDepth(node.depth).width)
        .fold<double>(0, math.max);
    final bottomEdge = nodes
        .map((node) => node.offset.dy + nodeSizeForDepth(node.depth).height)
        .fold<double>(0, math.max);
    final size = Size(
      (math.max(
        rightEdge + 120,
        maxDepth * 230 + 260,
      )).clamp(420, 2600).toDouble(),
      (bottomEdge + 96).clamp(460, 5200),
    );
    return _MindMapLayout(nodes: nodes, edges: edges, size: size);
  }

  static Size nodeSizeForDepth(int depth) {
    return depth == 0 ? const Size(190, 76) : const Size(176, 88);
  }

  static int _maxDepth(MeetingMindMapNode node) {
    if (node.children.isEmpty) return 1;
    return 1 + node.children.map(_maxDepth).reduce((a, b) => a > b ? a : b);
  }
}

class _MindMapLayoutNode {
  const _MindMapLayoutNode({
    required this.node,
    required this.offset,
    required this.depth,
  });

  final MeetingMindMapNode node;
  final Offset offset;
  final int depth;
}

class _MindMapEdge {
  const _MindMapEdge({
    required this.from,
    required this.to,
    required this.depth,
  });

  final Offset from;
  final Offset to;
  final int depth;
}

class _UnknownSpeakerPrompt extends StatelessWidget {
  const _UnknownSpeakerPrompt({
    required this.session,
    required this.controller,
    required this.onSeek,
  });

  final MeetingSession session;
  final MeetingController controller;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final unknownSpeakers = <String, MeetingTranscriptSegment>{};
    for (final segment in session.transcriptSegments) {
      final speakerId = segment.speakerId.trim();
      if (speakerId.isEmpty) continue;
      final label = session.speakerLabels[speakerId]?.trim() ?? '';
      if (label.isEmpty || label == speakerId) {
        unknownSpeakers.putIfAbsent(speakerId, () => segment);
      }
    }
    if (unknownSpeakers.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.appText(
                '未登録の話者がいます。声を確認してラベルを追加してください。',
                'Some speakers are unlabeled. Listen and add labels.',
              ),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final entry in unknownSpeakers.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.record_voice_over_rounded),
                title: Text(entry.key),
                subtitle: Text(
                  context.appText(
                    '${_formatSeconds(entry.value.startSeconds)} から再生して確認',
                    'Play from ${_formatSeconds(entry.value.startSeconds)} to check',
                  ),
                ),
                trailing: const Icon(Icons.edit_rounded),
                onTap: () => _playAndLabel(context, entry.key, entry.value),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _playAndLabel(
    BuildContext context,
    String speakerId,
    MeetingTranscriptSegment segment,
  ) async {
    onSeek(segment.startSeconds);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => SpeakerLabelDialog(
        title: context.appText('話者ラベルを追加', 'Add speaker label'),
        initialText: speakerId,
        helperText: context.appText(
          '${_formatSeconds(segment.startSeconds)} から声を再生しています。',
          'Playing voice from ${_formatSeconds(segment.startSeconds)}.',
        ),
      ),
    );
    if (label == null) return;
    await controller.updateSpeakerLabel(session.id, speakerId, label);
    await controller.renameSpeakerEverywhere(speakerId, label);
  }
}

class _TranscriptSection extends StatelessWidget {
  const _TranscriptSection({
    required this.session,
    required this.controller,
    required this.playbackPosition,
    this.onSeek,
  });

  final MeetingSession session;
  final MeetingController controller;
  final ValueNotifier<Duration> playbackPosition;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    if (session.transcriptSegments.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: _Section(
            title: context.appText('文字起こし', 'Transcript'),
            text: session.transcription.isEmpty
                ? context.appText('文字起こしがありません', 'No transcript')
                : _cleanDisplayText(session.transcription),
          ),
        ),
      );
    }
    return ValueListenableBuilder<Duration>(
      valueListenable: playbackPosition,
      builder: (context, position, _) {
        final seconds = position.inMilliseconds / 1000;
        return SliverMainAxisGroup(
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: _sectionTitle(
                  context,
                  context.appText('文字起こし', 'Transcript'),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverList.builder(
                itemCount: session.transcriptSegments.length,
                itemBuilder: (context, i) {
                  return _TranscriptTile(
                    segment: session.transcriptSegments[i],
                    session: session,
                    highlighted: _isCurrentSegment(i, seconds),
                    onSeek: onSeek,
                    onEditSpeaker: _editSpeaker,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  bool _isCurrentSegment(int index, double seconds) {
    final segment = session.transcriptSegments[index];
    final nextStart = index + 1 < session.transcriptSegments.length
        ? session.transcriptSegments[index + 1].startSeconds
        : segment.endSeconds;
    final end = segment.endSeconds > segment.startSeconds
        ? segment.endSeconds
        : nextStart;
    return seconds >= segment.startSeconds && seconds < end + 0.35;
  }

  Future<void> _editSpeaker(BuildContext context, String speakerId) async {
    final label = await showDialog<String>(
      context: context,
      builder: (context) => SpeakerLabelDialog(
        title: context.appText('話者名', 'Speaker name'),
        initialText: session.speakerLabels[speakerId] ?? speakerId,
      ),
    );
    if (label == null) {
      return;
    }
    await controller.updateSpeakerLabel(session.id, speakerId, label);
    await controller.renameSpeakerEverywhere(speakerId, label);
  }
}

class SpeakerLabelDialog extends StatefulWidget {
  const SpeakerLabelDialog({
    required this.title,
    required this.initialText,
    this.helperText = '',
    super.key,
  });

  final String title;
  final String initialText;
  final String helperText;

  @override
  State<SpeakerLabelDialog> createState() => _SpeakerLabelDialogState();
}

class _SpeakerLabelDialogState extends State<SpeakerLabelDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  late final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.helperText.trim().isNotEmpty) ...[
            Text(widget.helperText),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: context.appText('名前', 'Name'),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.appText('キャンセル', 'Cancel')),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(context.appText('保存', 'Save')),
        ),
      ],
    );
  }

  void _save() {
    Navigator.of(context).pop(_controller.text);
  }
}

class _TranscriptTile extends StatelessWidget {
  const _TranscriptTile({
    required this.segment,
    required this.session,
    required this.highlighted,
    required this.onEditSpeaker,
    this.onSeek,
  });

  final MeetingTranscriptSegment segment;
  final MeetingSession session;
  final bool highlighted;
  final Future<void> Function(BuildContext context, String speakerId)
  onEditSpeaker;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: highlighted
            ? colorScheme.primaryContainer.withValues(alpha: 0.55)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Text(_formatSeconds(segment.startSeconds)),
        title: Text(segment.text.trim()),
        subtitle: Text(
          session.speakerLabels[segment.speakerId] ??
              (segment.speakerId.isEmpty ? 'Speaker' : segment.speakerId),
        ),
        trailing: IconButton(
          tooltip: context.appText('話者名を編集', 'Edit speaker name'),
          icon: const Icon(Icons.edit_rounded),
          onPressed: segment.speakerId.isEmpty
              ? null
              : () => onEditSpeaker(context, segment.speakerId),
        ),
        onTap: onSeek == null ? null : () => onSeek!(segment.startSeconds),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(text),
          ),
        ),
      ],
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.title,
    required this.text,
    required this.onSpeak,
    required this.onStop,
  });

  final String title;
  final String text;
  final VoidCallback onSpeak;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle(context, title)),
            IconButton(
              tooltip: context.appText('要約を読み上げ', 'Read summary aloud'),
              icon: const Icon(Icons.volume_up_rounded),
              onPressed: text.trim().isEmpty ? null : onSpeak,
            ),
            IconButton(
              tooltip: context.appText('読み上げ停止', 'Stop reading aloud'),
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: onStop,
            ),
          ],
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(text),
          ),
        ),
      ],
    );
  }
}

class _Translations extends StatefulWidget {
  const _Translations({
    required this.session,
    required this.controller,
    required this.summaryText,
  });

  final MeetingSession session;
  final MeetingController controller;
  final String summaryText;

  @override
  State<_Translations> createState() => _TranslationsState();
}

class _TranslationsState extends State<_Translations> {
  int _selectedIndex = 0;
  bool _regenerating = false;

  @override
  Widget build(BuildContext context) {
    final translations = widget.controller.useEnglish
        ? <String, String>{
            '日本語':
                widget.session.translations['ja'] ?? widget.session.translation,
            '中文': widget.session.translations['zh'] ?? '',
            '한국어': widget.session.translations['ko'] ?? '',
          }
        : <String, String>{
            'English':
                widget.session.translations['en'] ?? widget.session.translation,
            '中文': widget.session.translations['zh'] ?? '',
            '한국어': widget.session.translations['ko'] ?? '',
          };
    translations.removeWhere((_, value) => value.trim().isEmpty);
    if (translations.isEmpty) {
      return _Section(
        title: widget.controller.strings.t('meeting.translation'),
        text: widget.controller.strings.t('meeting.noTranslation'),
      );
    }
    if (_selectedIndex >= translations.length) {
      _selectedIndex = 0;
    }
    final labels = translations.keys.toList(growable: false);
    final selectedText = translations[labels[_selectedIndex]] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionTitle(
                context,
                widget.controller.strings.t('meeting.translation'),
              ),
            ),
            IconButton(
              tooltip: widget.controller.strings.t(
                'meeting.translationRegenerate',
              ),
              icon: _regenerating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate_rounded),
              onPressed: _regenerating ? null : _regenerate,
            ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(labels[i]),
                    selected: i == _selectedIndex,
                    onSelected: (_) => setState(() => _selectedIndex = i),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(_cleanDisplayText(selectedText)),
          ),
        ),
      ],
    );
  }

  Future<void> _regenerate() async {
    setState(() => _regenerating = true);
    try {
      await widget.controller.regenerateTranslations(
        widget.session.id,
        summaryOverride: widget.summaryText,
      );
    } finally {
      if (mounted) {
        setState(() => _regenerating = false);
      }
    }
  }
}

class _WebSources extends StatelessWidget {
  const _WebSources({required this.sources, required this.controller});

  final List<WebSource> sources;
  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const SizedBox.shrink();
    }
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: false,
      leading: const Icon(Icons.travel_explore),
      title: Text(
        controller.strings.t('meeting.webSources'),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      children: [
        for (final source in sources.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.public),
            title: Text(source.title.isEmpty ? source.url : source.title),
            subtitle: Text(source.snippet),
            trailing: source.url.trim().isEmpty
                ? null
                : const Icon(Icons.open_in_new_rounded),
            onTap: source.url.trim().isEmpty
                ? null
                : () => InAppBrowserScreen.open(
                    context,
                    url: source.url,
                    title: source.title,
                  ),
          ),
      ],
    );
  }
}

class _TodoSection extends StatelessWidget {
  const _TodoSection({required this.session, required this.controller});

  final MeetingSession session;
  final MeetingController controller;

  @override
  Widget build(BuildContext context) {
    final todos = session.todoItems;
    if (todos.isEmpty) {
      return const _Section(title: 'TODO', text: 'TODOはありません');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'TODO',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            children: <Widget>[
              for (final item in todos)
                CheckboxListTile(
                  value: item.completed,
                  onChanged: (_) => controller.toggleTodo(session.id, item.id),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    '・${item.text}',
                    style: TextStyle(
                      decoration: item.completed
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _cleanDisplayText(String text) {
  return text
      .split('\n')
      .map((line) => line.trimRight().replaceFirst(RegExp(r'^\s*\*\s+'), '・'))
      .where((line) => !RegExp(r'^([*＊・\-—–•●○#\s])+$').hasMatch(line.trim()))
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _localizedTemplateTitle(
  String id,
  String fallback,
  BuildContext context,
) {
  final english = switch (id) {
    'meeting_minutes' => 'Meeting minutes',
    'todo_only' => 'Action items',
    'decision_log' => 'Decision log',
    'customer_research' => 'Customer research',
    'one_on_one' => 'One-on-one',
    'recruiting' => 'Recruiting',
    'book' => 'Book notes',
    'medical' => 'Medical notes',
    'project' => 'Project notes',
    'spec_review' => 'Spec review',
    'code_review' => 'Code review',
    'incident' => 'Incident report',
    'daily' => 'Daily standup',
    'weekly' => 'Weekly review',
    'business_report' => 'Business report',
    'user_test' => 'User test',
    'decisions_only' => 'Decisions',
    'risk' => 'Risk analysis',
    'faq' => 'FAQ',
    'keyword' => 'Keyword focus',
    'chronological' => 'Chronological summary',
    'speaker' => 'Speaker summary',
    'sentiment' => 'Sentiment analysis',
    'motivation' => 'Motivation analysis',
    'opposition' => 'Opposing views',
    'brief' => 'Brief summary',
    'detailed' => 'Detailed notes',
    'share_email' => 'Share email',
    'social' => 'Short share text',
    'press' => 'Press brief',
    'product' => 'Product notes',
    'sales' => 'Sales notes',
    'support' => 'Support log',
    'engineering' => 'Engineering notes',
    'design' => 'Design review',
    'research' => 'Research notes',
    'study' => 'Study notes',
    'interview' => 'Interview notes',
    'standup' => 'Standup',
    'retrospective' => 'Retrospective',
    'planning' => 'Planning',
    'brainstorm' => 'Brainstorm',
    'contract' => 'Contract review',
    'legal' => 'Legal review',
    'finance' => 'Finance notes',
    'hiring' => 'Hiring notes',
    'lecture' => 'Lecture notes',
    'workshop' => 'Workshop notes',
    'field' => 'Field report',
    'custom' => 'Custom',
    _ => fallback,
  };
  return context.appText(fallback, english);
}

String _localizedMeetingLabel(String value, BuildContext context) {
  final normalized = value.trim().toLowerCase();
  final english = switch (normalized) {
    '概要' || '要約' || 'summary' => 'Summary',
    'ノート' || 'notes' => 'Notes',
    'フォーマット' || 'format' => 'Format',
    '要約テンプレート' || 'summary template' => 'Summary template',
    '会議議事録' || 'meeting minutes' => 'Meeting minutes',
    'todo' || 'to do' || 'action items' || 'アクションアイテム' => 'Action items',
    '感情分析' ||
    'センチメンタル' ||
    'sentiment' ||
    'sentimental' ||
    'sentiment analysis' => 'Sentiment analysis',
    '原文メモ' || 'source notes' => 'Source notes',
    '詳細ノート' || 'detailed notes' => 'Detailed notes',
    '学習ノート' || 'study notes' => 'Study notes',
    'キーワード' || 'keywords' => 'Keywords',
    '重要マーク' || 'bookmarks' => 'Bookmarks',
    'ask suggestions' || 'aiに聞けること' => 'Ask suggestions',
    'マインドマップ' || 'mind map' || 'mindmap' => 'Mind map',
    '翻訳' || 'translation' => 'Translation',
    'ソース' || 'source' => 'Source',
    '論点' || 'issues' || 'discussion points' => 'Discussion points',
    '決定事項' || 'decisions' => 'Decisions',
    _ => value,
  };
  final japanese = switch (normalized) {
    'summary' => '要約',
    'notes' => 'ノート',
    'format' => 'フォーマット',
    'summary template' => '要約テンプレート',
    'meeting minutes' => '会議議事録',
    'action items' => 'TODO',
    'sentiment' || 'sentimental' || 'sentiment analysis' => '感情分析',
    'source notes' => '原文メモ',
    'detailed notes' => '詳細ノート',
    'study notes' => '学習ノート',
    'keywords' => 'キーワード',
    'bookmarks' => '重要マーク',
    'ask suggestions' => 'AIに聞けること',
    'mind map' => 'マインドマップ',
    'translation' => '翻訳',
    'source' => 'ソース',
    'issues' || 'discussion points' => '論点',
    'decisions' => '決定事項',
    _ => value,
  };
  return context.appText(japanese, english);
}

String _localizedMeetingText(String value, BuildContext context) {
  if (context.appUsesEnglish) {
    return value
        .replaceAll(RegExp(r'^概要\s*[:：]', multiLine: true), 'Summary:')
        .replaceAll(RegExp(r'^要約\s*[:：]', multiLine: true), 'Summary:')
        .replaceAll(RegExp(r'^ノート\s*[:：]', multiLine: true), 'Notes:')
        .replaceAll(RegExp(r'^フォーマット\s*[:：]', multiLine: true), 'Format:')
        .replaceAll(RegExp(r'^感情分析\s*[:：]', multiLine: true), 'Sentiment:')
        .replaceAll(RegExp(r'^センチメンタル\s*[:：]', multiLine: true), 'Sentiment:')
        .replaceAll(RegExp(r'^TODO\s*[:：]', multiLine: true), 'Action items:')
        .replaceAll(RegExp(r'^原文メモ\s*[:：]', multiLine: true), 'Source notes:')
        .replaceAll(
          RegExp(r'^詳細ノート\s*[:：]', multiLine: true),
          'Detailed notes:',
        )
        .replaceAll(RegExp(r'^学習ノート\s*[:：]', multiLine: true), 'Study notes:')
        .replaceAll(
          RegExp(r'^論点\s*[:：]', multiLine: true),
          'Discussion points:',
        )
        .replaceAll(RegExp(r'^決定事項\s*[:：]', multiLine: true), 'Decisions:')
        .replaceAll('満足度', 'Satisfaction')
        .replaceAll('モチベーション', 'Motivation')
        .replaceAll('懸念', 'Concern')
        .replaceAll(
          '音量と無音比率も加味しています。',
          'Audio volume and silence ratio are also included.',
        )
        .replaceAllMapped(RegExp(r'発話比率\s*(\d+)%?。?'), (match) {
          return ' Speech ratio ${match.group(1)}%.';
        });
  }
  return value
      .replaceAll(RegExp(r'^Summary\s*[:：]', multiLine: true), '要約:')
      .replaceAll(RegExp(r'^Notes\s*[:：]', multiLine: true), 'ノート:')
      .replaceAll(RegExp(r'^Format\s*[:：]', multiLine: true), 'フォーマット:')
      .replaceAll(
        RegExp(r'^Sentiment Analysis\s*[:：]', multiLine: true),
        '感情分析:',
      )
      .replaceAll(RegExp(r'^Sentiment\s*[:：]', multiLine: true), '感情分析:')
      .replaceAll(RegExp(r'^Sentimental\s*[:：]', multiLine: true), '感情分析:')
      .replaceAll(RegExp(r'^Action Items\s*[:：]', multiLine: true), 'TODO:')
      .replaceAll(RegExp(r'^Source Notes\s*[:：]', multiLine: true), '原文メモ:')
      .replaceAll(RegExp(r'^Detailed Notes\s*[:：]', multiLine: true), '詳細ノート:')
      .replaceAll(RegExp(r'^Study Notes\s*[:：]', multiLine: true), '学習ノート:')
      .replaceAll('Satisfaction', '満足度')
      .replaceAll('Motivation', 'モチベーション')
      .replaceAll('Concern', '懸念')
      .replaceAll(
        'Estimated from positive terms, concern terms, action terms, and filler frequency in the transcript.',
        '文字起こし内の前向きな表現、懸念表現、行動に関する表現、フィラーの頻度から推定しています。',
      )
      .replaceAll(
        'Audio volume and silence ratio are also included.',
        '音量と無音比率も加味しています。',
      )
      .replaceAllMapped(RegExp(r'Speech ratio\s*(\d+)%\.?'), (match) {
        return '発話比率 ${match.group(1)}%。';
      });
}

String _localizedSentimentSummary(
  MeetingSentimentMetrics sentiment,
  BuildContext context,
) {
  final raw = sentiment.summary.trim();
  final hasAudioContext =
      raw.contains('音量と無音比率') || raw.contains('Audio volume and silence ratio');
  final speechRatioMatch =
      RegExp(r'発話比率\s*(\d+)%?').firstMatch(raw) ??
      RegExp(r'Speech ratio\s*(\d+)%').firstMatch(raw);

  final buffer = StringBuffer(
    context.appText(
      '文字起こし内の前向きな表現、懸念表現、行動に関する表現、フィラーの頻度から推定しています。',
      'Estimated from positive terms, concern terms, action terms, and filler frequency in the transcript.',
    ),
  );
  if (hasAudioContext) {
    buffer.write(' ');
    buffer.write(
      context.appText(
        '音量と無音比率も加味しています。',
        'Audio volume and silence ratio are also included.',
      ),
    );
  }
  if (speechRatioMatch != null) {
    final ratio = speechRatioMatch.group(1);
    final speechText = context.appText(
      '発話比率 $ratio%。',
      'Speech ratio $ratio%.',
    );
    buffer.write(' ');
    buffer.write(speechText);
  }
  return buffer.toString().trim();
}

String _takeTextRunes(String value, int maxRunes) {
  final runes = value.runes.toList(growable: false);
  if (runes.length <= maxRunes) {
    return value;
  }
  return '${String.fromCharCodes(runes.take(maxRunes - 1))}…';
}

String _cleanSpeechTextForTts(String text) {
  return text
      .split('\n')
      .map((line) {
        return line
            .replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '')
            .replaceFirst(RegExp(r'^\s*[*＊]+\s*'), '')
            .replaceAll(RegExp(r'[*＊]+'), '')
            .trim();
      })
      .where((line) => line.isNotEmpty)
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _mindMapNodeLabel(MeetingMindMapNode node, BuildContext context) {
  final candidates = <String>[node.label, node.summary];
  for (final candidate in candidates) {
    final cleaned = candidate
        .replaceAll(RegExp(r'[#*＊`]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isNotEmpty) {
      return _localizedMeetingLabel(cleaned, context);
    }
  }
  return context.appText('項目', 'Item');
}

Widget _sectionTitle(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

String _formatDuration(Duration duration) {
  final total = duration.inSeconds.clamp(0, 24 * 60 * 60);
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}

String _formatSeconds(double seconds) {
  return _formatDuration(Duration(seconds: seconds.round()));
}

class _MeetingChatView extends StatefulWidget {
  const _MeetingChatView({
    required this.session,
    required this.controller,
    this.initialQuestion = '',
  });

  final MeetingSession session;
  final MeetingController controller;
  final String initialQuestion;

  @override
  State<_MeetingChatView> createState() => _MeetingChatViewState();
}

class _MeetingChatViewState extends State<_MeetingChatView> {
  final TextEditingController _textController = TextEditingController();
  bool _isGenerating = false;
  bool _webSearchEnabled = true;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestion.trim().isNotEmpty) {
      _textController.text = widget.initialQuestion.trim();
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isGenerating) return;

    setState(() {
      _isGenerating = true;
      _textController.clear();
    });

    try {
      final currentSession = widget.controller.sessions.firstWhere(
        (session) => session.id == widget.session.id,
        orElse: () => widget.session,
      );
      await widget.controller.askMeetingQuestion(
        currentSession,
        text,
        useWeb: _webSearchEnabled,
      );
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.appText(
              'エラーが発生しました ($error)',
              'An error occurred ($error)',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.76,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.appText('会議について質問', 'Ask about the meeting'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _webSearchEnabled ? Icons.travel_explore : Icons.public_off,
                  ),
                  color: _webSearchEnabled
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  tooltip: _webSearchEnabled
                      ? context.appText('Web検索オン', 'Web search on')
                      : context.appText('Web検索オフ', 'Web search off'),
                  onPressed: () {
                    setState(() {
                      _webSearchEnabled = !_webSearchEnabled;
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: widget.controller.sessions
                  .firstWhere(
                    (session) => session.id == widget.session.id,
                    orElse: () => widget.session,
                  )
                  .consultations
                  .length,
              itemBuilder: (context, index) {
                final message = widget.controller.sessions
                    .firstWhere(
                      (session) => session.id == widget.session.id,
                      orElse: () => widget.session,
                    )
                    .consultations[index];
                return Align(
                  alignment: message.isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: message.isUser
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(message.text),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isGenerating) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: InputDecoration(
                      hintText: context.appText(
                        '質問を入力...',
                        'Type a question...',
                      ),
                    ),
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  tooltip: context.appText('送信', 'Send'),
                  onPressed: _isGenerating ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
