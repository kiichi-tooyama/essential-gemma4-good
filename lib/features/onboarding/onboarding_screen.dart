import 'package:flutter/material.dart';

import '../../app/app_language.dart';
import '../model_management/model_management_controller.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.controller,
    required this.onFinished,
    required this.onOpenModels,
    super.key,
  });

  final ModelManagementController controller;
  final VoidCallback onFinished;
  final VoidCallback onOpenModels;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          scheme.primaryContainer,
                          scheme.secondaryContainer,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Essential',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.appText(
                            '写真も声もテキストも、気軽にAIへ相談できるトークアプリ。',
                            'A chat app for casually asking AI with photos, voice, or text.',
                          ),
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _IntroChip(
                              icon: Icons.shield_rounded,
                              label: context.appText('端末内AI', 'On-device AI'),
                            ),
                            _IntroChip(
                              icon: Icons.wifi_off_rounded,
                              label: context.appText('オフラインOK', 'Offline OK'),
                            ),
                            _IntroChip(
                              icon: Icons.photo_camera_rounded,
                              label: context.appText(
                                '写真も使える',
                                'Works with photos',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: <Widget>[
                        _OnboardingPage(
                          icon: Icons.chat_bubble_rounded,
                          title: context.appText(
                            'DMみたいにAIへ話せる',
                            'Talk to AI like a DM',
                          ),
                          description: context.appText(
                            '聞きたいことをそのまま送るだけ。写真を添付したり、声で話しかけたりできます。',
                            'Send what you want to ask as-is. You can attach photos or speak by voice.',
                          ),
                          footer: _MetricRow(
                            metrics: <_MetricItem>[
                              _MetricItem(
                                label: context.appText('入力', 'Input'),
                                value: context.appText(
                                  '声/写真/文字',
                                  'Voice/photo/text',
                                ),
                              ),
                              _MetricItem(
                                label: context.appText('会話', 'Chat'),
                                value: context.appText(
                                  '日本語OK',
                                  'English ready',
                                ),
                              ),
                              _MetricItem(
                                label: context.appText('気軽さ', 'Ease'),
                                value: context.appText('すぐ相談', 'Ask instantly'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      TextButton(
                        onPressed: widget.onFinished,
                        child: Text(context.appText('あとで設定する', 'Set up later')),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: widget.onFinished,
                        icon: const Icon(Icons.chat_bubble_rounded),
                        label: Text(context.appText('はじめる', 'Start')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.footer,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 268),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: scheme.onSecondaryContainer),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 22),
              footer,
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metrics});

  final List<_MetricItem> metrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: metrics
          .map(
            (metric) => Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      metric.label,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      metric.value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MetricItem {
  const _MetricItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _IntroChip extends StatelessWidget {
  const _IntroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}
