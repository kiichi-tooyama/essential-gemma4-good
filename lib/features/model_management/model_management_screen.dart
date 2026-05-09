import 'package:flutter/material.dart';

import '../../app/app_language.dart';
import '../../app/runtime_health_controller.dart';
import 'model_management_controller.dart';
import 'model_management_models.dart';

class ModelManagementScreen extends StatefulWidget {
  const ModelManagementScreen({
    required this.controller,
    required this.runtimeHealthController,
    super.key,
  });

  final ModelManagementController controller;
  final RuntimeHealthController runtimeHealthController;

  @override
  State<ModelManagementScreen> createState() => _ModelManagementScreenState();
}

class _ModelManagementScreenState extends State<ModelManagementScreen> {
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
        final controller = widget.controller;
        final visibleCatalog = controller.catalog
            .where((entry) => controller.isModelVisibleInSetup(entry.modelId))
            .toList();
        final chatEntries = visibleCatalog.where(_isChatCatalogEntry).toList();
        final voiceEntries = visibleCatalog
            .where(_isVoiceCatalogEntry)
            .toList();
        final otherEntries = visibleCatalog
            .where(
              (entry) =>
                  !_isChatCatalogEntry(entry) && !_isVoiceCatalogEntry(entry),
            )
            .toList();
        final visibleBundles = controller.bundles
            .where(controller.isBundleVisibleInSetup)
            .toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(context.appText('AIを追加', 'Add AI')),
            actions: <Widget>[
              IconButton(
                onPressed: controller.refreshCatalog,
                icon: const Icon(Icons.refresh),
                tooltip: context.appText('更新', 'Refresh'),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: controller.refreshCatalog,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                _StorageSummaryCard(snapshot: controller.storageSnapshot),
                const SizedBox(height: 16),
                _DeviceRecommendationCard(
                  runtimeHealthController: widget.runtimeHealthController,
                ),
                const SizedBox(height: 16),
                _QuickSetupPanel(
                  controller: controller,
                  onDownloadRecommended: () => _runAction(
                    controller.downloadRecommended,
                    successMessage: context.appText(
                      'おすすめAIの準備を始めました。',
                      'Started setting up the recommended AI.',
                    ),
                  ),
                  onDownloadHighAccuracy: () => _runAction(
                    controller.downloadHighAccuracyChat,
                    successMessage: context.appText(
                      '高精度チャットAIの準備を始めました。',
                      'Started setting up the high-accuracy chat AI.',
                    ),
                  ),
                  onDownloadAll: () => _runAction(
                    controller.downloadEverything,
                    successMessage: context.appText(
                      '使えるAIをまとめて準備します。',
                      'Setting up all available AI assets.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (controller.isOfflineMode)
                  _ErrorCard(
                    message: context.appText(
                      'ネットワーク断を検知しました。ローカル推論は継続し、モデル配信はオフラインモードで待機します。',
                      'Network is unavailable. Local inference will continue and model delivery will wait in offline mode.',
                    ),
                  ),
                if (controller.catalogError != null)
                  _ErrorCard(message: controller.catalogError!),
                if (controller.isLoading && controller.catalog.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...<Widget>[
                  _CatalogSection(
                    title: context.appText('チャットAI', 'Chat AI'),
                    subtitle: context.appText(
                      '普段の相談と写真理解で使うAIです。',
                      'Used for everyday questions and photo understanding.',
                    ),
                    emptyMessage: context.appText(
                      '追加できるチャットAIはまだありません。',
                      'There is no chat AI to add yet.',
                    ),
                    children: <Widget>[
                      for (final entry in chatEntries) ...<Widget>[
                        _modelCardFor(entry),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  _CatalogSection(
                    title: context.appText('音声AI', 'Voice AI'),
                    subtitle: context.appText(
                      'Essential Live の聞き取りと読み上げに使います。',
                      'Used for Essential Live listening and speech.',
                    ),
                    emptyMessage: context.appText(
                      '追加できる音声AIはまだありません。',
                      'There is no voice AI to add yet.',
                    ),
                    children: <Widget>[
                      for (final entry in voiceEntries) ...<Widget>[
                        _modelCardFor(entry),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                  if (otherEntries.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    _CatalogSection(
                      title: context.appText('その他', 'Other'),
                      subtitle: context.appText(
                        '補助的なAIパーツです。',
                        'Supplemental AI components.',
                      ),
                      emptyMessage: context.appText(
                        '追加できるAIパーツはまだありません。',
                        'There are no AI components to add yet.',
                      ),
                      children: <Widget>[
                        for (final entry in otherEntries) ...<Widget>[
                          _modelCardFor(entry),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  _CatalogSection(
                    title: context.appText('機能セット', 'Feature sets'),
                    subtitle: context.appText(
                      '必要なAIをまとめて準備できます。',
                      'Set up the AI assets needed for a feature together.',
                    ),
                    emptyMessage: context.appText(
                      '使える機能セットはまだありません。',
                      'There are no available feature sets yet.',
                    ),
                    children: <Widget>[
                      for (final entry in visibleBundles) ...<Widget>[
                        _bundleCardFor(entry),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                  const SizedBox(height: 20),
                  _CatalogSection(
                    title: context.appText('インストール済み', 'Installed'),
                    subtitle: context.appText(
                      'この端末で使えるAIです。',
                      'AI assets available on this device.',
                    ),
                    emptyMessage: context.appText(
                      'まだインストール済みのAIはありません。',
                      'No AI assets are installed yet.',
                    ),
                    children: <Widget>[
                      for (final record in controller.installedModels)
                        if (_isVisibleSetupModelId(record.modelId)) ...<Widget>[
                          _InstalledModelTile(
                            record: record,
                            onDelete: () => _runAction(
                              () => controller.deleteModel(record.modelId),
                              successMessage: context.appUsesEnglish
                                  ? 'Deleted ${record.displayName}.'
                                  : '${record.displayName} を削除しました。',
                            ),
                            onTogglePin: () => _runAction(
                              () => controller.togglePin(record.modelId),
                              successMessage: context.appUsesEnglish
                                  ? record.isPinned
                                        ? 'Unpinned ${record.displayName}.'
                                        : 'Pinned ${record.displayName}.'
                                  : record.isPinned
                                  ? '${record.displayName} のピン留めを解除しました。'
                                  : '${record.displayName} をピン留めしました。',
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      for (final record in controller.installedBundles)
                        if (_isVisibleSetupBundleId(
                          record.bundleId,
                        )) ...<Widget>[
                          _InstalledBundleTile(
                            record: record,
                            onDelete: () => _runAction(
                              () => controller.deleteBundle(record.bundleId),
                              successMessage: context.appUsesEnglish
                                  ? 'Deleted ${record.displayName}.'
                                  : '${record.displayName} を削除しました。',
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    await action();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  Widget _modelCardFor(ModelCatalogEntry entry) {
    final controller = widget.controller;
    return _ModelCatalogCard(
      controller: controller,
      recommendation: widget.runtimeHealthController.recommendationFor(entry),
      entry: entry,
      state: controller.stateFor(entry),
      progress: controller.progressFor(entry.modelId),
      installation: controller.installationFor(entry.modelId),
      errorMessage: controller.errorFor(entry.modelId),
      onDownload: () => _runAction(
        () => controller.downloadModel(entry),
        successMessage: context.appUsesEnglish
            ? 'Started setting up ${_friendlyModelTitle(entry, context)}.'
            : '${_friendlyModelTitle(entry, context)} の準備を始めました。',
      ),
      onDelete: () => _runAction(
        () => controller.deleteModel(entry.modelId),
        successMessage: context.appUsesEnglish
            ? 'Deleted ${_friendlyModelTitle(entry, context)}.'
            : '${_friendlyModelTitle(entry, context)} を削除しました。',
      ),
      onTogglePin: () => _runAction(
        () => controller.togglePin(entry.modelId),
        successMessage: context.appUsesEnglish
            ? controller.installationFor(entry.modelId)!.isPinned
                  ? 'Unpinned ${_friendlyModelTitle(entry, context)}.'
                  : 'Pinned ${_friendlyModelTitle(entry, context)}.'
            : controller.installationFor(entry.modelId)!.isPinned
            ? '${_friendlyModelTitle(entry, context)} の固定を外しました。'
            : '${_friendlyModelTitle(entry, context)} を固定しました。',
      ),
    );
  }

  Widget _bundleCardFor(BundleCatalogEntry entry) {
    final controller = widget.controller;
    return _BundleCatalogCard(
      controller: controller,
      entry: entry,
      progress: controller.bundleProgressFor(entry.bundleId),
      componentProgress: controller.bundleComponentProgressFor(entry.bundleId),
      errorMessage: controller.bundleErrorFor(entry.bundleId),
      installation: controller.bundleInstallationFor(entry.bundleId),
      isDownloading: controller.isBundleDownloading(entry.bundleId),
      onDownload: () => _runAction(
        () => controller.downloadBundle(entry),
        successMessage: context.appUsesEnglish
            ? 'Started setting up ${_friendlyBundleTitle(entry, context)}.'
            : '${_friendlyBundleTitle(entry, context)} の準備を始めました。',
      ),
      onDelete: () => _runAction(
        () => controller.deleteBundle(entry.bundleId),
        successMessage: context.appUsesEnglish
            ? 'Deleted ${_friendlyBundleTitle(entry, context)}.'
            : '${_friendlyBundleTitle(entry, context)} を削除しました。',
      ),
    );
  }
}

class _CatalogSection extends StatelessWidget {
  const _CatalogSection({
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.children,
  });

  final String title;
  final String subtitle;
  final String emptyMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(subtitle),
        const SizedBox(height: 12),
        if (children.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(emptyMessage),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

class _StorageSummaryCard extends StatelessWidget {
  const _StorageSummaryCard({required this.snapshot});

  final StorageSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.appText('保存スペース', 'Storage'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.appText(
                '${_formatBytes(snapshot.usedBytes)} / ${_formatBytes(snapshot.quotaBytes)} を使用中',
                '${_formatBytes(snapshot.usedBytes)} / ${_formatBytes(snapshot.quotaBytes)} used',
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: snapshot.usageRatio),
            const SizedBox(height: 8),
            Text(
              context.appText(
                '使えるAI ${snapshot.installedCount} 個',
                'Available AI: ${snapshot.installedCount}',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.appText(
                '共有パーツ ${snapshot.sharedComponentCount} 個',
                'Shared components: ${snapshot.sharedComponentCount}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickSetupPanel extends StatelessWidget {
  const _QuickSetupPanel({
    required this.controller,
    required this.onDownloadRecommended,
    required this.onDownloadHighAccuracy,
    required this.onDownloadAll,
  });

  final ModelManagementController controller;
  final VoidCallback onDownloadRecommended;
  final VoidCallback onDownloadHighAccuracy;
  final VoidCallback onDownloadAll;

  @override
  Widget build(BuildContext context) {
    final installedModelCount = controller.installedModels
        .where((record) => _isVisibleSetupModelId(record.modelId))
        .length;
    final installedBundleCount = controller.installedBundles
        .where((record) => _isVisibleSetupBundleId(record.bundleId))
        .length;
    final totalModelCount = controller.catalog
        .where((entry) => controller.isModelVisibleInSetup(entry.modelId))
        .length;
    final totalBundleCount = controller.bundles
        .where(controller.isBundleVisibleInSetup)
        .length;
    final busy =
        controller.isLoading ||
        controller.catalog.any(
          (entry) =>
              controller.stateFor(entry) == ModelAvailabilityState.downloading,
        ) ||
        controller.bundles.any(
          (entry) => controller.isBundleDownloading(entry.bundleId),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.appText('はじめる準備', 'Setup'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.appText(
                '使えるAI: $installedModelCount/$totalModelCount · 機能セット $installedBundleCount/$totalBundleCount',
                'Available AI: $installedModelCount/$totalModelCount · Feature sets $installedBundleCount/$totalBundleCount',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.appText(
                '迷ったらおすすめでOK。チャットと音声に必要なものをまとめて準備します。',
                'If you are unsure, start with the recommendation. It sets up what chat and voice need.',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: busy ? null : onDownloadRecommended,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(context.appText('おすすめで始める', 'Recommended')),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onDownloadHighAccuracy,
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: Text(context.appText('高精度AIを入れる', 'High accuracy AI')),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onDownloadAll,
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: Text(context.appText('全部使えるようにする', 'Set up all')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelCatalogCard extends StatelessWidget {
  const _ModelCatalogCard({
    required this.controller,
    required this.recommendation,
    required this.entry,
    required this.state,
    required this.progress,
    required this.installation,
    required this.errorMessage,
    required this.onDownload,
    required this.onDelete,
    required this.onTogglePin,
  });

  final ModelManagementController controller;
  final ModelRecommendation recommendation;
  final ModelCatalogEntry entry;
  final ModelAvailabilityState state;
  final double progress;
  final InstalledModelRecord? installation;
  final String? errorMessage;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                Text(
                  _friendlyModelTitle(entry, context),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                _StateChip(state: state),
                Chip(
                  avatar: Icon(
                    recommendation.recommended
                        ? Icons.thumb_up_alt_rounded
                        : Icons.warning_amber_rounded,
                    size: 18,
                  ),
                  label: Text(
                    recommendation.recommended
                        ? context.appText('おすすめ', 'Recommended')
                        : context.appText('重いかも', 'May be heavy'),
                  ),
                ),
                if (installation?.isPinned ?? false)
                  Chip(
                    avatar: const Icon(Icons.push_pin, size: 18),
                    label: Text(context.appText('固定中', 'Pinned')),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_friendlyModelSummary(entry, context)),
            const SizedBox(height: 8),
            Text(recommendation.reason),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                _InfoPill(label: _friendlyModelType(entry, context)),
                _InfoPill(label: '${entry.downloadSizeMb} MB'),
                _InfoPill(
                  label: context.appText(
                    '目安RAM ${_formatRam(entry.recommendedRamMb)}',
                    'RAM guide ${_formatRam(entry.recommendedRamMb)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text(context.appText('詳しい情報', 'Details')),
              children: <Widget>[
                _DetailLine(
                  label: context.appText('モデルID', 'Model ID'),
                  value: entry.modelId,
                ),
                _DetailLine(
                  label: context.appText('バージョン', 'Version'),
                  value: entry.version,
                ),
                _DetailLine(
                  label: context.appText('実行方式', 'Runtime'),
                  value: entry.runtime,
                ),
                _DetailLine(
                  label: context.appText('ライセンス', 'License'),
                  value: entry.license,
                ),
                _DetailLine(
                  label: context.appText('種類', 'Variant'),
                  value: entry.variantId,
                ),
              ],
            ),
            if (state == ModelAvailabilityState.downloading) ...<Widget>[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 8),
              Text(
                context.appText(
                  '準備 ${(progress * 100).toStringAsFixed(0)}%',
                  'Preparing ${(progress * 100).toStringAsFixed(0)}%',
                ),
              ),
            ],
            if (errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (entry.supportsAdapters) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                context.appText('追加スタイル', 'Add-on styles'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                context.appText(
                  '返し方や得意分野を変えられます。',
                  'Change response style or specialty.',
                ),
              ),
              const SizedBox(height: 8),
              ..._buildAdapters(context),
            ],
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: _buildActions(context)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    switch (state) {
      case ModelAvailabilityState.notInstalled:
      case ModelAvailabilityState.failed:
        return <Widget>[
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.download),
            label: Text(context.appText('使えるようにする', 'Enable')),
          ),
        ];
      case ModelAvailabilityState.downloading:
        return <Widget>[
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.downloading),
            label: Text(context.appText('準備中', 'Preparing')),
          ),
        ];
      case ModelAvailabilityState.available:
        if (controller.isModelAvailableThroughBundle(entry.modelId)) {
          return <Widget>[
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                context.appText('機能セットで使用可能', 'Available via feature set'),
              ),
            ),
          ];
        }
        return <Widget>[
          OutlinedButton.icon(
            onPressed: onTogglePin,
            icon: Icon(
              installation?.isPinned ?? false
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
            ),
            label: Text(
              installation?.isPinned ?? false
                  ? context.appText('固定を外す', 'Unpin')
                  : context.appText('固定', 'Pin'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: Text(context.appText('削除', 'Delete')),
          ),
        ];
      case ModelAvailabilityState.updateAvailable:
        return <Widget>[
          FilledButton.icon(
            onPressed: onDownload,
            icon: const Icon(Icons.system_update_alt),
            label: Text(context.appText('更新を取得', 'Get update')),
          ),
          OutlinedButton.icon(
            onPressed: onTogglePin,
            icon: Icon(
              installation?.isPinned ?? false
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
            ),
            label: Text(
              installation?.isPinned ?? false
                  ? context.appText('固定を外す', 'Unpin')
                  : context.appText('固定', 'Pin'),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: Text(context.appText('削除', 'Delete')),
          ),
        ];
    }
  }

  List<Widget> _buildAdapters(BuildContext context) {
    final adapters = controller.catalogAdaptersForModel(entry.modelId);
    if (adapters.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            context.appText(
              'このAI向けの追加スタイルはまだありません。',
              'There are no add-on styles for this AI yet.',
            ),
          ),
        ),
      ];
    }

    return adapters
        .map(
          (adapter) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AdapterCatalogTile(
              entry: adapter,
              installation: controller.adapterInstallationFor(
                adapter.adapterId,
              ),
              progress: controller.adapterProgressFor(adapter.adapterId),
              errorMessage: controller.adapterErrorFor(adapter.adapterId),
              isDownloading: controller.isAdapterDownloading(adapter.adapterId),
              isCompatible: controller.isAdapterCompatible(
                adapter,
                installation,
              ),
              onDownload: () => controller.downloadAdapter(adapter),
              onDelete: () => controller.deleteAdapter(adapter.adapterId),
            ),
          ),
        )
        .toList();
  }
}

class _DeviceRecommendationCard extends StatelessWidget {
  const _DeviceRecommendationCard({required this.runtimeHealthController});

  final RuntimeHealthController runtimeHealthController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              context.appText('端末適合性', 'Device fit'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(runtimeHealthController.deviceHealthLabel()),
            const SizedBox(height: 8),
            Text(
              context.appText(
                '低 RAM / 省電力端末では、軽量モデルを優先して推奨します。',
                'On low-RAM or power-saving devices, lighter models are recommended first.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdapterCatalogTile extends StatelessWidget {
  const _AdapterCatalogTile({
    required this.entry,
    required this.installation,
    required this.progress,
    required this.errorMessage,
    required this.isDownloading,
    required this.isCompatible,
    required this.onDownload,
    required this.onDelete,
  });

  final AdapterCatalogEntry entry;
  final InstalledAdapterRecord? installation;
  final double progress;
  final String? errorMessage;
  final bool isDownloading;
  final bool isCompatible;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Text(
                entry.displayName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Chip(label: Text(entry.namespaceId)),
              if (installation != null) const Chip(label: Text('Installed')),
              if (!isCompatible)
                Chip(
                  label: Text(context.appText('非互換', 'Incompatible')),
                  avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(entry.summary),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _InfoPill(label: 'v${entry.version}'),
              _InfoPill(label: entry.runtime),
              if (entry.compatibleVariantIds.isNotEmpty)
                _InfoPill(
                  label: 'Variant ${entry.compatibleVariantIds.join(", ")}',
                ),
              if (entry.compatibleQuantizations.isNotEmpty)
                _InfoPill(
                  label:
                      '${context.appText('量子化', 'Quantization')} ${entry.compatibleQuantizations.join(", ")}',
                ),
            ],
          ),
          if (entry.taskProfile.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Task: ${entry.taskProfile.entries.map((e) => "${e.key}=${e.value}").join(" / ")}',
            ),
          ],
          if (entry.supportedModalities.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text('Modalities: ${entry.supportedModalities.join(", ")}'),
          ],
          if (isDownloading) ...<Widget>[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress == 0 ? null : progress),
          ],
          if (errorMessage != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: <Widget>[
              if (installation == null)
                FilledButton.icon(
                  onPressed: isCompatible && !isDownloading ? onDownload : null,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(context.appText('インストール', 'Install')),
                )
              else
                OutlinedButton.icon(
                  onPressed: isDownloading ? null : onDelete,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(context.appText('削除', 'Delete')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BundleCatalogCard extends StatelessWidget {
  const _BundleCatalogCard({
    required this.controller,
    required this.entry,
    required this.progress,
    required this.componentProgress,
    required this.errorMessage,
    required this.installation,
    required this.isDownloading,
    required this.onDownload,
    required this.onDelete,
  });

  final ModelManagementController controller;
  final BundleCatalogEntry entry;
  final double progress;
  final Map<String, double> componentProgress;
  final String? errorMessage;
  final InstalledBundleRecord? installation;
  final bool isDownloading;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Text(
                  _friendlyBundleTitle(entry, context),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (installation != null)
                  Chip(label: Text(context.appText('使える', 'Available'))),
                ...entry.taskProfiles.map(
                  (String task) =>
                      Chip(label: Text(_friendlyTaskLabel(task, context))),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_friendlyBundleSummary(entry, context)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _InfoPill(label: '${entry.downloadSizeMb} MB'),
                _InfoPill(
                  label: context.appText(
                    '目安RAM ${_formatRam(entry.recommendedRamMb)}',
                    'RAM guide ${_formatRam(entry.recommendedRamMb)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: Text(context.appText('中身を見る', 'View contents')),
              children: entry.nodes.map((BundleNode node) {
                final componentInstallation = controller
                    .componentInstallationFor(node.modelId);
                final shared = controller.isComponentShared(node.modelId);
                final nodeProgress = componentProgress[node.modelId];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            Text(
                              _friendlyComponentTitle(node.modelId, context),
                            ),
                            Chip(
                              label: Text(
                                _friendlyNodeType(node.type, context),
                              ),
                            ),
                            if (shared)
                              Chip(
                                avatar: const Icon(
                                  Icons.hub_outlined,
                                  size: 18,
                                ),
                                label: Text(context.appText('共有中', 'Shared')),
                              ),
                            if (componentInstallation != null)
                              Chip(
                                label: Text(
                                  context.appText('使える', 'Available'),
                                ),
                              ),
                          ],
                        ),
                        if (nodeProgress != null) ...<Widget>[
                          const SizedBox(height: 8),
                          LinearProgressIndicator(value: nodeProgress),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            if (isDownloading) ...<Widget>[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progress == 0 ? null : progress),
              const SizedBox(height: 8),
              Text(
                context.appText(
                  '準備 ${(progress * 100).toStringAsFixed(0)}%',
                  'Preparing ${(progress * 100).toStringAsFixed(0)}%',
                ),
              ),
            ],
            if (errorMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: <Widget>[
                if (installation == null)
                  FilledButton.icon(
                    onPressed: isDownloading ? null : onDownload,
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(context.appText('使えるようにする', 'Enable')),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: isDownloading ? null : onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(context.appText('削除', 'Delete')),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InstalledBundleTile extends StatelessWidget {
  const _InstalledBundleTile({required this.record, required this.onDelete});

  final InstalledBundleRecord record;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(_friendlyInstalledBundleTitle(record.displayName, context)),
        subtitle: Text(
          context.appText(
            '${record.componentModelIds.length}個のAIパーツ',
            '${record.componentModelIds.length} AI components',
          ),
        ),
        trailing: IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          tooltip: context.appText('削除', 'Delete'),
        ),
      ),
    );
  }
}

class _InstalledModelTile extends StatelessWidget {
  const _InstalledModelTile({
    required this.record,
    required this.onDelete,
    required this.onTogglePin,
  });

  final InstalledModelRecord record;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          _friendlyInstalledModelTitle(
            record.modelId,
            record.displayName,
            context,
          ),
        ),
        subtitle: Text(
          context.appText(
            '${_formatBytes(record.sizeBytes)} · 詳細は設定から確認できます',
            '${_formatBytes(record.sizeBytes)} · Details are available in Settings',
          ),
        ),
        trailing: Wrap(
          spacing: 8,
          children: <Widget>[
            IconButton(
              onPressed: onTogglePin,
              icon: Icon(
                record.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              tooltip: record.isPinned
                  ? context.appText('固定を外す', 'Unpin')
                  : context.appText('固定', 'Pin'),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: context.appText('削除', 'Delete'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final ModelAvailabilityState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (state) {
      ModelAvailabilityState.notInstalled => (
        scheme.surfaceContainerHighest,
        scheme.onSurface,
      ),
      ModelAvailabilityState.downloading => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      ModelAvailabilityState.available => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      ModelAvailabilityState.updateAvailable => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      ModelAvailabilityState.failed => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };

    return Chip(
      backgroundColor: background,
      labelStyle: TextStyle(color: foreground),
      label: Text(state.localizedLabel(context.appUsesEnglish)),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
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

String _formatRam(int megabytes) {
  if (megabytes >= 1024) {
    return '${(megabytes / 1024).toStringAsFixed(0)}GB';
  }
  return '${megabytes}MB';
}

String _friendlyModelTitle(ModelCatalogEntry entry, BuildContext context) {
  return _friendlyInstalledModelTitle(
    entry.modelId,
    entry.displayName,
    context,
  );
}

String _friendlyInstalledModelTitle(
  String modelId,
  String fallback,
  BuildContext context,
) {
  if (modelId == 'gemma-4-e4b-it') {
    return context.appText('高精度チャットAI', 'High-accuracy chat AI');
  }
  if (modelId == 'gemma-4-e2b-it') {
    return context.appText('軽めのチャットAI', 'Light chat AI');
  }
  if (modelId == 'gemma-4-e4b-litertlm-it') {
    return context.appText('高精度Gemma Live AI', 'High-accuracy Gemma Live AI');
  }
  if (modelId == 'gemma-4-e2b-litertlm-it') {
    return context.appText('標準Gemma Live AI', 'Standard Gemma Live AI');
  }
  if (modelId == 'whisper-base') {
    return context.appText('高精度会議文字起こしAI', 'Accurate meeting transcription AI');
  }
  if (modelId == 'whisper-tiny') {
    return context.appText('軽量会議文字起こしAI', 'Light meeting transcription AI');
  }
  if (modelId.startsWith('whisper')) {
    return context.appText('会議文字起こしAI', 'Meeting transcription AI');
  }
  return fallback;
}

String _friendlyModelSummary(ModelCatalogEntry entry, BuildContext context) {
  if (entry.modelId == 'gemma-4-e4b-litertlm-it') {
    return context.appText(
      '品質を優先したGemmaの端末内チャットモデルです。Essential LiveやChatで使います。',
      'A quality-focused on-device Gemma chat model for Essential Live and Chat.',
    );
  }
  if (entry.modelId == 'gemma-4-e2b-litertlm-it') {
    return context.appText(
      '速度と品質のバランスがよいGemmaの端末内チャットモデルです。まずこれを入れます。',
      'A balanced on-device Gemma chat model. This is the recommended first install.',
    );
  }
  if (entry.modelId == 'gemma-4-e4b-it') {
    return context.appText(
      'しっかり相談したい時向け。長めの会話や文章づくりに向いています。',
      'For deeper conversations and longer writing tasks.',
    );
  }
  if (entry.modelId == 'gemma-4-e2b-it') {
    return context.appText(
      '軽めにサクッと話したい時向け。端末負荷を抑えやすいAIです。',
      'For quick lightweight chats with lower device load.',
    );
  }
  if (entry.modelId == 'whisper-base') {
    return context.appText(
      '会議音声の文字起こし精度を優先するWhisperモデルです。',
      'A Whisper model for more accurate meeting transcription.',
    );
  }
  if (entry.modelId == 'whisper-tiny') {
    return context.appText(
      '容量を抑えて会議音声を文字起こしするWhisperモデルです。',
      'A compact Whisper model for meeting transcription.',
    );
  }
  if (entry.modelId.startsWith('whisper')) {
    return context.appText(
      '会議アシスタントでMP3やWAVを取り込んだ時に、端末内で文字起こしするためのWhisperモデルです。',
      'An on-device Whisper model for transcribing imported MP3 and WAV meeting audio.',
    );
  }
  return entry.summary;
}

String _friendlyModelType(ModelCatalogEntry entry, BuildContext context) {
  if (entry.runtime == 'google-ai-edge-litertlm') {
    return context.appText('チャット', 'Chat');
  }
  if (entry.runtime == 'whisper.cpp') {
    return context.appText('会議文字起こし', 'Meeting transcription');
  }
  if (entry.runtime == 'text') {
    return context.appText('補助データ', 'Support data');
  }
  return entry.runtime;
}

String _friendlyBundleTitle(BundleCatalogEntry entry, BuildContext context) {
  if (entry.bundleId.contains('speech')) {
    return context.appText('音声会話セット', 'Voice conversation set');
  }
  if (entry.bundleId.contains('e4b')) {
    return context.appText('高精度チャットセット', 'High-accuracy chat set');
  }
  if (entry.bundleId.contains('e2b')) {
    return context.appText('軽めのチャットセット', 'Light chat set');
  }
  if (entry.bundleId.contains('lite')) {
    return context.appText('お試しチャットセット', 'Trial chat set');
  }
  return entry.displayName;
}

String _friendlyInstalledBundleTitle(String displayName, BuildContext context) {
  final lower = displayName.toLowerCase();
  if (lower.contains('speech')) {
    return context.appText('音声会話セット', 'Voice conversation set');
  }
  if (lower.contains('e4b')) {
    return context.appText('高精度チャットセット', 'High-accuracy chat set');
  }
  if (lower.contains('e2b')) {
    return context.appText('軽めのチャットセット', 'Light chat set');
  }
  if (lower.contains('lite')) {
    return context.appText('お試しチャットセット', 'Trial chat set');
  }
  return displayName;
}

String _friendlyBundleSummary(BundleCatalogEntry entry, BuildContext context) {
  if (entry.bundleId.contains('speech')) {
    return context.appText(
      '音声入力と読み上げをまとめて使えるようにします。',
      'Enables voice input and speech output together.',
    );
  }
  if (entry.bundleId.contains('e4b')) {
    return context.appText(
      '高精度なチャットAIを使うためのセットです。',
      'A set for using high-accuracy chat AI.',
    );
  }
  if (entry.bundleId.contains('e2b')) {
    return context.appText(
      '軽めのチャットAIを使うためのセットです。',
      'A set for using light chat AI.',
    );
  }
  if (entry.bundleId.contains('lite')) {
    return context.appText(
      '容量を抑えてまず試すためのセットです。',
      'A compact set for trying Essential first.',
    );
  }
  return entry.summary;
}

String _friendlyTaskLabel(String task, BuildContext context) {
  return switch (task) {
    'TEXT_GENERATION' => context.appText('トーク', 'Talk'),
    'CHAT' => context.appText('チャット', 'Chat'),
    'SPEECH_TO_TEXT' => context.appText('音声入力', 'Voice input'),
    'TEXT_TO_SPEECH' => context.appText('読み上げ', 'Speech output'),
    _ => task,
  };
}

String _friendlyComponentTitle(String modelId, BuildContext context) {
  return _friendlyInstalledModelTitle(modelId, modelId, context);
}

String _friendlyNodeType(String type, BuildContext context) {
  return switch (type) {
    'base' => context.appText('本体', 'Core'),
    'stt' => context.appText('音声入力', 'Voice input'),
    'tts' => context.appText('読み上げ', 'Speech output'),
    _ => type,
  };
}

bool _isChatCatalogEntry(ModelCatalogEntry entry) {
  return entry.modelId == 'gemma-4-e2b-litertlm-it' ||
      entry.modelId == 'gemma-4-e4b-litertlm-it';
}

bool _isVoiceCatalogEntry(ModelCatalogEntry entry) {
  return entry.modelId == 'whisper-tiny' || entry.modelId == 'whisper-base';
}

bool _isVisibleSetupModelId(String modelId) {
  return const <String>{
    'gemma-4-e2b-litertlm-it',
    'gemma-4-e4b-litertlm-it',
    'whisper-tiny',
    'whisper-base',
  }.contains(modelId);
}

bool _isVisibleSetupBundleId(String bundleId) {
  return bundleId == 'essential-chat-gemma-4-e2b-it-mobile-bundle' ||
      bundleId == 'essential-chat-gemma-4-e4b-it-mobile-bundle';
}
