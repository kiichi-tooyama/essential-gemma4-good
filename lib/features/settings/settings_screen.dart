import 'package:flutter/material.dart';

import '../../app/app_preferences_controller.dart';
import '../../app/app_language.dart';
import '../../app/runtime_health_controller.dart';
import '../model_management/model_management_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.preferencesController,
    required this.modelController,
    required this.runtimeHealthController,
    required this.onReplayOnboarding,
    super.key,
  });

  final AppPreferencesController preferencesController;
  final ModelManagementController modelController;
  final RuntimeHealthController runtimeHealthController;
  final VoidCallback onReplayOnboarding;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.modelController.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.preferencesController,
        widget.modelController,
      ]),
      builder: (context, _) {
        final preference = widget.preferencesController.themePreference;
        final language = widget.preferencesController.languagePreference;
        final strings = widget.preferencesController.languagePack;
        final storage = widget.modelController.storageSnapshot;
        final telemetry =
            widget.runtimeHealthController.telemetryController.summary;
        return Scaffold(
          appBar: AppBar(title: Text(strings.t('settings.title'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _SectionCard(
                title: strings.t('settings.theme.title'),
                subtitle: strings.t('settings.theme.subtitle'),
                child: SegmentedButton<AppThemePreference>(
                  segments: <ButtonSegment<AppThemePreference>>[
                    ButtonSegment<AppThemePreference>(
                      value: AppThemePreference.system,
                      icon: const Icon(Icons.brightness_auto_rounded),
                      label: Text(strings.t('settings.theme.system')),
                    ),
                    ButtonSegment<AppThemePreference>(
                      value: AppThemePreference.light,
                      icon: const Icon(Icons.light_mode_rounded),
                      label: Text(strings.t('settings.theme.light')),
                    ),
                    ButtonSegment<AppThemePreference>(
                      value: AppThemePreference.dark,
                      icon: const Icon(Icons.dark_mode_rounded),
                      label: Text(strings.t('settings.theme.dark')),
                    ),
                  ],
                  selected: <AppThemePreference>{preference},
                  onSelectionChanged: (selection) {
                    widget.preferencesController.updateThemePreference(
                      selection.first,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: strings.t('settings.language.title'),
                subtitle: strings.t('settings.language.subtitle'),
                child: SegmentedButton<AppLanguagePreference>(
                  segments: const <ButtonSegment<AppLanguagePreference>>[
                    ButtonSegment<AppLanguagePreference>(
                      value: AppLanguagePreference.japanese,
                      icon: Icon(Icons.language_rounded),
                      label: Text('日本語'),
                    ),
                    ButtonSegment<AppLanguagePreference>(
                      value: AppLanguagePreference.english,
                      icon: Icon(Icons.translate_rounded),
                      label: Text('English'),
                    ),
                  ],
                  selected: <AppLanguagePreference>{language},
                  onSelectionChanged: (selection) {
                    widget.preferencesController.updateLanguagePreference(
                      selection.first,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: strings.t('settings.safety.title'),
                subtitle: strings.t('settings.safety.subtitle'),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    Chip(
                      avatar: const Icon(Icons.memory_rounded, size: 18),
                      label: Text(strings.t('settings.safety.local')),
                    ),
                    Chip(
                      avatar: const Icon(Icons.wifi_off_rounded, size: 18),
                      label: Text(strings.t('settings.safety.offline')),
                    ),
                    Chip(
                      avatar: const Icon(Icons.cloud_off_rounded, size: 18),
                      label: Text(strings.t('settings.safety.noCloud')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: strings.t('settings.location.title'),
                subtitle: strings.t('settings.location.subtitle'),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(strings.t('settings.location.toggle')),
                  subtitle: Text(strings.t('settings.location.toggleSubtitle')),
                  value: widget.preferencesController.locationSearchEnabled,
                  onChanged: (value) => widget.preferencesController
                      .updateLocationSearchEnabled(value),
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: strings.t('settings.storage.title'),
                subtitle: strings.t('settings.storage.subtitle'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      strings
                          .t('settings.storage.used')
                          .replaceAll('{used}', _formatBytes(storage.usedBytes))
                          .replaceAll(
                            '{quota}',
                            _formatBytes(storage.quotaBytes),
                          ),
                    ),
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: storage.usageRatio),
                    const SizedBox(height: 10),
                    Text(
                      strings
                          .t('settings.storage.installed')
                          .replaceAll(
                            '{count}',
                            storage.installedCount.toString(),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: strings.t('settings.device.title'),
                subtitle: strings.t('settings.device.subtitle'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.runtimeHealthController.deviceHealthLabel()),
                    const SizedBox(height: 10),
                    Text(
                      strings
                          .t('settings.device.recentUse')
                          .replaceAll(
                            '{count}',
                            widget.runtimeHealthController.recentInferenceCount
                                .toString(),
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: strings.t('settings.developer.title'),
                subtitle: strings.t('settings.developer.subtitle'),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(strings.t('settings.developer.details')),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: <Widget>[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(strings.t('settings.telemetry.title')),
                      subtitle: Text(strings.t('settings.telemetry.subtitle')),
                      value: widget.preferencesController.telemetryEnabled,
                      onChanged: (value) async {
                        await widget.preferencesController
                            .updateTelemetryEnabled(value);
                        await widget.runtimeHealthController
                            .syncTelemetryConsent();
                      },
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            strings
                                .t('settings.telemetry.downloadSuccess')
                                .replaceAll(
                                  '{count}',
                                  telemetry.downloadSuccessCount.toString(),
                                ),
                          ),
                          Text(
                            strings
                                .t('settings.telemetry.downloadFailure')
                                .replaceAll(
                                  '{count}',
                                  telemetry.downloadFailureCount.toString(),
                                ),
                          ),
                          Text(
                            strings
                                .t('settings.telemetry.inferenceCount')
                                .replaceAll(
                                  '{count}',
                                  telemetry.inferenceCount.toString(),
                                ),
                          ),
                          Text(
                            strings
                                .t('settings.telemetry.averageSpeed')
                                .replaceAll(
                                  '{ms}',
                                  telemetry.averageInferenceLatencyMs
                                      .toStringAsFixed(0),
                                ),
                          ),
                          Text(
                            strings
                                .t('settings.telemetry.recoveryCount')
                                .replaceAll(
                                  '{count}',
                                  telemetry.runtimeRecoveryCount.toString(),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: strings.t('settings.onboarding.title'),
                subtitle: strings.t('settings.onboarding.subtitle'),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: widget.onReplayOnboarding,
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(strings.t('settings.onboarding.open')),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(subtitle),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) {
    return '0 MB';
  }
  final megabytes = bytes / (1024 * 1024);
  if (megabytes >= 1024) {
    return '${(megabytes / 1024).toStringAsFixed(1)} GB';
  }
  return '${megabytes.toStringAsFixed(1)} MB';
}
