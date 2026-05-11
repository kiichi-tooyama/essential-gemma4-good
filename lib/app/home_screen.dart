import 'dart:async';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_preferences_controller.dart';
import 'runtime_health_controller.dart';
import '../features/chat/chat_controller.dart';
import '../features/chat/chat_screen.dart';
import '../features/chat/voice_live_screen.dart';
import '../features/model_management/model_management_controller.dart';
import '../features/model_management/model_management_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/meeting_assistant/meeting_controller.dart';
import '../features/meeting_assistant/meeting_list_screen.dart';

class EssentialHomeScreen extends StatefulWidget {
  const EssentialHomeScreen({
    required this.controller,
    required this.preferencesController,
    required this.runtimeHealthController,
    required this.onReplayOnboarding,
    this.initialIndex = 0,
    this.smokeModelPath,
    this.smokePrompt,
    this.smokePrompts = const <String>[],
    this.smokeImagePaths = const <String>[],
    this.smokeAudioPaths = const <String>[],
    super.key,
  });

  final ModelManagementController controller;
  final AppPreferencesController preferencesController;
  final RuntimeHealthController runtimeHealthController;
  final VoidCallback onReplayOnboarding;
  final int initialIndex;
  final String? smokeModelPath;
  final String? smokePrompt;
  final List<String> smokePrompts;
  final List<String> smokeImagePaths;
  final List<String> smokeAudioPaths;

  @override
  State<EssentialHomeScreen> createState() => _EssentialHomeScreenState();
}

class _EssentialHomeScreenState extends State<EssentialHomeScreen> {
  late int _selectedIndex = widget.initialIndex;
  late final Set<int> _visitedIndexes = <int>{_selectedIndex};
  final ChatController _chatController = ChatController();
  late final MeetingController _meetingController = MeetingController(
    modelController: widget.controller,
    chatController: _chatController,
    preferencesController: widget.preferencesController,
  );

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _meetingController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EssentialHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _selectedIndex = widget.initialIndex;
      _visitedIndexes.add(_selectedIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.preferencesController.languagePack;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          for (final index in _visitedIndexes)
            Offstage(
              offstage: index != _selectedIndex,
              child: TickerMode(
                enabled: index == _selectedIndex,
                child: _buildPage(index),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectIndex,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: strings.t('nav.home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: const Icon(Icons.chat_bubble_rounded),
            label: strings.t('nav.chat'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.mic_none_rounded),
            selectedIcon: const Icon(Icons.mic_rounded),
            label: strings.t('nav.meetings'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome_rounded),
            label: strings.t('nav.ai'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline_rounded),
            selectedIcon: const Icon(Icons.person_rounded),
            label: strings.t('nav.settings'),
          ),
        ],
      ),
    );
  }

  void _selectIndex(int index) {
    if (index == 2) {
      unawaited(_meetingController.initialize());
    }
    setState(() {
      _selectedIndex = index;
      _visitedIndexes.add(index);
    });
  }

  Widget _buildPage(int index) {
    return switch (index) {
      0 => _ForYouScreen(
        controller: widget.controller,
        preferencesController: widget.preferencesController,
        onOpenChat: _openNewChatFromHome,
        onOpenVoice: _openVoiceLive,
        onOpenModels: () => _selectIndex(3),
      ),
      1 => ChatScreen(
        controller: widget.controller,
        chatController: _chatController,
        preferencesController: widget.preferencesController,
        runtimeHealthController: widget.runtimeHealthController,
        onOpenModels: () => _selectIndex(3),
        smokeModelPath: widget.smokeModelPath,
        smokePrompt: widget.smokePrompt,
        smokePrompts: widget.smokePrompts,
        smokeImagePaths: widget.smokeImagePaths,
        smokeAudioPaths: widget.smokeAudioPaths,
      ),
      2 => _LazyMeetingPage(controller: _meetingController),
      3 => ModelManagementScreen(
        controller: widget.controller,
        runtimeHealthController: widget.runtimeHealthController,
      ),
      _ => SettingsScreen(
        preferencesController: widget.preferencesController,
        modelController: widget.controller,
        runtimeHealthController: widget.runtimeHealthController,
        onReplayOnboarding: widget.onReplayOnboarding,
      ),
    };
  }

  Future<void> _openVoiceLive() async {
    await _chatController.initialize();
    await _chatController.createSession();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VoiceLiveScreen(
          chatController: _chatController,
          modelController: widget.controller,
          preferencesController: widget.preferencesController,
          runtimeHealthController: widget.runtimeHealthController,
        ),
      ),
    );
  }

  Future<void> _openNewChatFromHome() async {
    await _chatController.initialize();
    await _chatController.createSession();
    if (!mounted) {
      return;
    }
    _selectIndex(1);
  }
}

class _LazyMeetingPage extends StatefulWidget {
  const _LazyMeetingPage({required this.controller});

  final MeetingController controller;

  @override
  State<_LazyMeetingPage> createState() => _LazyMeetingPageState();
}

class _LazyMeetingPageState extends State<_LazyMeetingPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return MeetingListScreen(controller: widget.controller);
  }
}

class _ForYouScreen extends StatefulWidget {
  const _ForYouScreen({
    required this.controller,
    required this.preferencesController,
    required this.onOpenChat,
    required this.onOpenVoice,
    required this.onOpenModels,
  });

  final ModelManagementController controller;
  final AppPreferencesController preferencesController;
  final FutureOr<void> Function() onOpenChat;
  final VoidCallback onOpenVoice;
  final VoidCallback onOpenModels;

  @override
  State<_ForYouScreen> createState() => _ForYouScreenState();
}

class _ForYouScreenState extends State<_ForYouScreen> {
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
        final strings = widget.preferencesController.languagePack;
        final readyAi = _chatReadyCount(widget.controller);
        final hasChat = readyAi > 0;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Essential'),
            actions: <Widget>[
              IconButton(
                onPressed: widget.onOpenModels,
                icon: const Icon(Icons.add_circle_outline_rounded),
                tooltip: strings.t('home.addAi'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              SizedBox(
                height: 106,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    _StoryBubble(
                      icon: Icons.chat_bubble_rounded,
                      label: strings.t('home.story.chat'),
                      accent: Theme.of(context).colorScheme.primary,
                      onTap: () =>
                          unawaited(Future<void>.sync(widget.onOpenChat)),
                    ),
                    _StoryBubble(
                      icon: Icons.photo_camera_rounded,
                      label: strings.t('home.story.photo'),
                      accent: Theme.of(context).colorScheme.secondary,
                      onTap: () =>
                          unawaited(Future<void>.sync(widget.onOpenChat)),
                    ),
                    _StoryBubble(
                      icon: Icons.mic_rounded,
                      label: strings.t('home.story.voice'),
                      accent: Theme.of(context).colorScheme.tertiary,
                      onTap: widget.onOpenVoice,
                    ),
                    _StoryBubble(
                      icon: Icons.auto_awesome_rounded,
                      label: strings.t('home.addAi'),
                      accent: Theme.of(context).colorScheme.primary,
                      onTap: widget.onOpenModels,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _HeroPostCard(
                strings: strings,
                readyAi: readyAi,
                hasChat: hasChat,
                onOpenChat: widget.onOpenChat,
                onOpenModels: widget.onOpenModels,
              ),
              const SizedBox(height: 16),
              _PromptStrip(strings: strings, onOpenChat: widget.onOpenChat),
              const SizedBox(height: 16),
              _FeatureGrid(
                strings: strings,
                onOpenChat: widget.onOpenChat,
                onOpenVoice: widget.onOpenVoice,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(44),
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: <Widget>[
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      accent,
                      Color.lerp(
                        accent,
                        Theme.of(context).colorScheme.secondary,
                        0.55,
                      )!,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: accent),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPostCard extends StatelessWidget {
  const _HeroPostCard({
    required this.strings,
    required this.readyAi,
    required this.hasChat,
    required this.onOpenChat,
    required this.onOpenModels,
  });

  final AppLanguagePack strings;
  final int readyAi;
  final bool hasChat;
  final FutureOr<void> Function() onOpenChat;
  final VoidCallback onOpenModels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1.28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: const <Color>[
                    Color(0xFF27324A),
                    Color(0xFF176B68),
                    Color(0xFF414A5F),
                  ],
                ),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 20,
                    child: Text(
                      strings.t(
                        hasChat
                            ? 'home.hero.readyTitle'
                            : 'home.hero.setupTitle',
                      ),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 18,
                    top: 18,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          readyAi == 0
                              ? strings.t('home.hero.preparing')
                              : strings
                                    .t('home.hero.readyCount')
                                    .replaceAll('{count}', readyAi.toString()),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  hasChat
                      ? strings.t('home.hero.readySubtitle')
                      : strings.t('home.hero.setupSubtitle'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: hasChat
                            ? () => unawaited(Future<void>.sync(onOpenChat))
                            : onOpenModels,
                        icon: Icon(
                          hasChat
                              ? Icons.chat_bubble_rounded
                              : Icons.download_rounded,
                        ),
                        label: Text(
                          strings.t(
                            hasChat ? 'home.hero.openChat' : 'home.addAi',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.outlined(
                      onPressed: onOpenModels,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      tooltip: strings.t('home.hero.availableAi'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptStrip extends StatelessWidget {
  const _PromptStrip({required this.strings, required this.onOpenChat});

  final AppLanguagePack strings;
  final FutureOr<void> Function() onOpenChat;

  @override
  Widget build(BuildContext context) {
    final prompts = <String>[
      strings.t('home.prompt.rewrite'),
      strings.t('home.prompt.photo'),
      strings.t('home.prompt.voice'),
      strings.t('home.prompt.schedule'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.t('home.prompt.title'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: prompts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => ActionChip(
              avatar: const Icon(Icons.bolt_rounded, size: 18),
              label: Text(prompts[index]),
              onPressed: () => unawaited(Future<void>.sync(onOpenChat)),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({
    required this.strings,
    required this.onOpenChat,
    required this.onOpenVoice,
  });

  final AppLanguagePack strings;
  final FutureOr<void> Function() onOpenChat;
  final VoidCallback onOpenVoice;

  @override
  Widget build(BuildContext context) {
    final items = <(_FeatureInfo, _FeatureInfo)>[
      (
        _FeatureInfo(
          Icons.image_rounded,
          strings.t('home.feature.photo.title'),
          strings.t('home.feature.photo.subtitle'),
        ),
        _FeatureInfo(
          Icons.graphic_eq_rounded,
          strings.t('home.feature.voice.title'),
          strings.t('home.feature.voice.subtitle'),
        ),
      ),
      (
        _FeatureInfo(
          Icons.edit_note_rounded,
          strings.t('home.feature.note.title'),
          strings.t('home.feature.note.subtitle'),
        ),
        _FeatureInfo(
          Icons.lock_rounded,
          strings.t('home.feature.local.title'),
          strings.t('home.feature.local.subtitle'),
        ),
      ),
    ];
    return Column(
      children: <Widget>[
        for (final row in items) ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _FeatureTile(
                  info: row.$1,
                  onTap: () => unawaited(Future<void>.sync(onOpenChat)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FeatureTile(
                  info: row.$2,
                  onTap: row.$2.title == strings.t('home.feature.voice.title')
                      ? onOpenVoice
                      : () => unawaited(Future<void>.sync(onOpenChat)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _FeatureInfo {
  const _FeatureInfo(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.info, required this.onTap});

  final _FeatureInfo info;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(info.icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(info.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(info.subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

int _chatReadyCount(ModelManagementController controller) {
  final paths = <String>{};
  for (final record in controller.installedModels) {
    if (_isChatModelId(record.modelId)) {
      paths.add(record.activePath);
    }
  }
  for (final bundle in controller.installedBundles) {
    for (final componentId in bundle.componentModelIds) {
      final component = controller.componentInstallationFor(componentId);
      if (component == null) {
        continue;
      }
      if (component.runtime == 'llama.cpp' &&
          component.format == 'gguf' &&
          component.type == 'base') {
        paths.add(component.activePath);
      }
    }
  }
  return paths.length;
}

bool _isChatModelId(String modelId) {
  return modelId == 'essential-mini' ||
      modelId == 'gemma-4-e2b-it' ||
      modelId == 'gemma-4-e4b-it';
}
