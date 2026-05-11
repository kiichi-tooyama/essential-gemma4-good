import 'package:flutter/material.dart';
import 'meeting_controller.dart';
import 'meeting_enhancements.dart';
import 'meeting_models.dart';
import 'meeting_recording_screen.dart';
import 'meeting_detail_screen.dart';

class MeetingListScreen extends StatefulWidget {
  const MeetingListScreen({required this.controller, super.key});

  final MeetingController controller;

  @override
  State<MeetingListScreen> createState() => _MeetingListScreenState();
}

class _MeetingListScreenState extends State<MeetingListScreen> {
  String _query = '';
  String _folderFilter = '';
  String _sourceFilter = '';

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final strings = widget.controller.strings;
        if (widget.controller.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(strings.t('meeting.allFiles')),
            actions: [
              IconButton(
                tooltip: strings.t('meeting.search'),
                icon: const Icon(Icons.manage_search_rounded),
                onPressed: _openSearch,
              ),
            ],
          ),
          body: widget.controller.sessions.isEmpty
              ? _buildEmptyState()
              : _buildLibrary(),
          floatingActionButton: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FloatingActionButton.extended(
                heroTag: 'import',
                onPressed: () => widget.controller.importMeetingAudio(),
                icon: const Icon(Icons.file_upload),
                label: Text(strings.t('meeting.importFile')),
              ),
              const SizedBox(height: 16),
              FloatingActionButton.extended(
                heroTag: 'record',
                onPressed: _openRecording,
                icon: const Icon(Icons.mic),
                label: Text(strings.t('meeting.record')),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mic_none_rounded, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            widget.controller.strings.t('meeting.emptyTitle'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(widget.controller.strings.t('meeting.emptySubtitle')),
        ],
      ),
    );
  }

  Widget _buildLibrary() {
    final strings = widget.controller.strings;
    final sessions = _filteredSessions();
    final folders = widget.controller.folders;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
      children: [
        Row(
          children: [
            ChoiceChip(
              label: Text(
                '${strings.t('meeting.allFilesCount')} (${widget.controller.sessions.length})',
              ),
              selected: _folderFilter.isEmpty,
              onSelected: (_) => setState(() {
                _folderFilter = '';
                _sourceFilter = '';
              }),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(
                '${strings.t('meeting.uncategorized')} (${_uncategorizedCount()})',
              ),
              selected: _folderFilter == '_uncategorized',
              onSelected: (_) =>
                  setState(() => _folderFilter = '_uncategorized'),
            ),
          ],
        ),
        if (_query.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            '${strings.t('meeting.search')}: $_query',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Text(
              strings.t('meeting.folders'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Spacer(),
            IconButton(
              tooltip: strings.t('meeting.addFolder'),
              icon: const Icon(Icons.add_rounded),
              onPressed: _createFolder,
            ),
          ],
        ),
        for (final folder in folders.take(6))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(folder),
            subtitle: Text(
              strings
                  .t('meeting.itemsCount')
                  .replaceAll('{count}', _folderCount(folder).toString()),
            ),
            selected: _folderFilter == folder,
            trailing: const Icon(Icons.more_horiz_rounded),
            onTap: () => setState(() => _folderFilter = folder),
          ),
        if (folders.length > 6)
          TextButton(onPressed: () {}, child: Text(strings.t('meeting.more'))),
        const SizedBox(height: 18),
        Text(
          strings.t('meeting.sources'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _sourceChip(
              strings.t('meeting.allSources'),
              '',
              count: widget.controller.sessions.length,
            ),
            _sourceChip(strings.t('meeting.source.mic'), 'mic'),
            _sourceChip(strings.t('meeting.source.device'), 'internal_audio'),
            _sourceChip(strings.t('meeting.source.import'), 'import'),
            if (_sourceCount('note_pin') > 0)
              _sourceChip('NotePin', 'note_pin'),
          ],
        ),
        const SizedBox(height: 6),
        const SizedBox(height: 22),
        _buildList(sessions),
      ],
    );
  }

  Widget _buildList(List<MeetingSession> sessions) {
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Text(widget.controller.strings.t('meeting.noResults')),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(session.title),
          subtitle: Text(
            session.status == MeetingStatus.processing
                ? _processingText(session)
                : '${session.createdAt.year}-${session.createdAt.month.toString().padLeft(2, '0')}-${session.createdAt.day.toString().padLeft(2, '0')} '
                      '${session.createdAt.hour.toString().padLeft(2, '0')}:${session.createdAt.minute.toString().padLeft(2, '0')} | '
                      '${_formatDuration(session.durationSeconds)}'
                      '${session.tags.isEmpty ? '' : ' | ${session.tags.take(3).join(', ')}'}',
          ),
          trailing: session.status == MeetingStatus.processing
              ? Text(
                  widget.controller.strings.t('meeting.generating'),
                  style: const TextStyle(color: Colors.teal),
                )
              : null,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MeetingDetailScreen(
                  session: session,
                  controller: widget.controller,
                ),
              ),
            );
          },
          onLongPress: () => _openSessionActions(session),
        );
      },
    );
  }

  Widget _sourceChip(String label, String source, {int? count}) {
    return FilterChip(
      avatar: const Icon(Icons.radio_button_checked_rounded, size: 16),
      label: Text('$label (${count ?? _sourceCount(source)})'),
      selected: _sourceFilter == source,
      onSelected: (_) => setState(() => _sourceFilter = source),
      visualDensity: VisualDensity.compact,
    );
  }

  int _sourceCount(String source) {
    return widget.controller.sessions
        .where((session) => session.recordingSource == source)
        .length;
  }

  void _openRecording() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MeetingRecordingScreen(controller: widget.controller),
      ),
    );
  }

  List<MeetingSession> _filteredSessions() {
    Iterable<MeetingSession> sessions = widget.controller.sessions;
    if (_folderFilter == '_uncategorized') {
      sessions = sessions.where((session) => session.folderId.isEmpty);
    } else if (_folderFilter.isNotEmpty) {
      sessions = sessions.where((session) => session.folderId == _folderFilter);
    }
    if (_sourceFilter.isNotEmpty) {
      sessions = sessions.where(
        (session) => session.recordingSource == _sourceFilter,
      );
    }
    if (_query.trim().isNotEmpty) {
      final ids = MeetingTextProcessor.search(
        sessions.toList(growable: false),
        _query,
      ).map((result) => result.session.id).toSet();
      sessions = sessions.where((session) => ids.contains(session.id));
    }
    return sessions.toList(growable: false);
  }

  int _uncategorizedCount() {
    return widget.controller.sessions
        .where((session) => session.folderId.isEmpty)
        .length;
  }

  int _folderCount(String folder) {
    return widget.controller.sessions
        .where((session) => session.folderId == folder)
        .length;
  }

  Future<void> _openSearch() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _TextInputDialog(
        title: widget.controller.strings.t('meeting.fullTextSearch'),
        initialText: _query,
        hintText: widget.controller.strings.t('meeting.keywordHint'),
        primaryLabel: widget.controller.strings.t('meeting.search'),
        secondaryLabel: widget.controller.strings.t('common.clear'),
        secondaryValue: '',
      ),
    );
    if (value != null) {
      setState(() => _query = value);
    }
  }

  Future<void> _createFolder() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _TextInputDialog(
        title: widget.controller.strings.t('meeting.folderName'),
        hintText: widget.controller.strings.t('meeting.folderHint'),
        primaryLabel: widget.controller.strings.t('common.create'),
        cancelLabel: widget.controller.strings.t('common.cancel'),
      ),
    );
    if (value != null && value.trim().isNotEmpty) {
      await widget.controller.createFolder(value.trim());
      if (!mounted) {
        return;
      }
      setState(() => _folderFilter = value.trim());
    }
  }

  Future<void> _openSessionActions(MeetingSession session) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(widget.controller.strings.t('meeting.moveToFolder')),
              subtitle: Text(
                session.folderId.isEmpty
                    ? widget.controller.strings.t('meeting.uncategorized')
                    : session.folderId,
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _moveSessionToFolder(session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: Text(widget.controller.strings.t('meeting.editTags')),
              subtitle: Text(
                session.tags.isEmpty
                    ? widget.controller.strings.t('meeting.noTags')
                    : session.tags.join(', '),
              ),
              onTap: () async {
                Navigator.of(context).pop();
                await _editSessionTags(session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_add_outlined),
              title: Text(widget.controller.strings.t('meeting.bookmarkStart')),
              onTap: () {
                widget.controller.addBookmark(session.id, 0);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveSessionToFolder(MeetingSession session) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _TextInputDialog(
        title: widget.controller.strings.t('meeting.destinationFolder'),
        initialText: session.folderId,
        hintText: widget.controller.strings.t('meeting.folderHint'),
        primaryLabel: widget.controller.strings.t('common.move'),
        cancelLabel: widget.controller.strings.t('common.cancel'),
        secondaryLabel: widget.controller.strings.t(
          'meeting.moveToUncategorized',
        ),
        secondaryValue: '',
      ),
    );
    if (value != null) {
      await widget.controller.setSessionFolder(session.id, value.trim());
      if (!mounted) {
        return;
      }
      setState(() => _folderFilter = value.trim());
    }
  }

  Future<void> _editSessionTags(MeetingSession session) async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => _TextInputDialog(
        title: widget.controller.strings.t('meeting.tags'),
        initialText: session.tags.join(', '),
        hintText: widget.controller.strings.t('meeting.tagsHint'),
        primaryLabel: widget.controller.strings.t('common.save'),
        cancelLabel: widget.controller.strings.t('common.cancel'),
      ),
    );
    if (value != null) {
      await widget.controller.setSessionTags(
        session.id,
        value.split(RegExp(r'[,、\s]+')).where((tag) => tag.isNotEmpty).toList(),
      );
    }
  }

  String _processingText(MeetingSession session) {
    final stage = session.processingStage.trim().isEmpty
        ? widget.controller.strings.t('meeting.processing')
        : session.processingStage.trim();
    final detail = session.processingDetail.trim();
    if (detail.isEmpty) {
      return stage;
    }
    return '$stage - $detail';
  }

  String _formatDuration(int seconds) {
    final total = seconds.clamp(0, 24 * 60 * 60);
    if (total <= 0) {
      return widget.controller.strings.t('meeting.unknownDuration');
    }
    final minutes = total ~/ 60;
    return '$minutes${widget.controller.strings.t('meeting.minutesSuffix')}';
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.primaryLabel,
    this.initialText = '',
    this.hintText = '',
    this.cancelLabel = 'キャンセル',
    this.secondaryLabel,
    this.secondaryValue,
  });

  final String title;
  final String initialText;
  final String hintText;
  final String primaryLabel;
  final String cancelLabel;
  final String? secondaryLabel;
  final String? secondaryValue;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
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
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: widget.hintText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        if (widget.secondaryLabel != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(widget.secondaryValue),
            child: Text(widget.secondaryLabel!),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.primaryLabel)),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }
}
