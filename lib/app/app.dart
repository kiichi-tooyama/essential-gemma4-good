import 'dart:async';

import 'package:flutter/material.dart';

import 'anonymous_telemetry_controller.dart';
import 'app_language.dart';
import 'app_preferences_controller.dart';
import 'runtime_health_controller.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'home_screen.dart';
import '../features/model_management/model_management_controller.dart';
import '../shared/theme/app_theme.dart';

class EssentialApp extends StatefulWidget {
  const EssentialApp({
    super.key,
    ModelManagementController? controller,
    this.smokeModelPath,
    this.smokePrompt,
    this.smokePrompts = const <String>[],
    this.smokeImagePaths = const <String>[],
    this.smokeAudioPaths = const <String>[],
  }) : _controller = controller;

  final ModelManagementController? _controller;
  final String? smokeModelPath;
  final String? smokePrompt;
  final List<String> smokePrompts;
  final List<String> smokeImagePaths;
  final List<String> smokeAudioPaths;

  @override
  State<EssentialApp> createState() => _EssentialAppState();
}

class _EssentialAppState extends State<EssentialApp> {
  late final AnonymousTelemetryController _telemetryController =
      AnonymousTelemetryController();
  late final ModelManagementController _controller =
      widget._controller ??
      ModelManagementController.createDefault(
        telemetryController: _telemetryController,
      );
  late final AppPreferencesController _preferencesController =
      AppPreferencesController();
  late final RuntimeHealthController _runtimeHealthController =
      RuntimeHealthController(
        preferencesController: _preferencesController,
        telemetryController: _telemetryController,
      );
  int _homeIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _controller.dispose();
    _telemetryController.dispose();
    _runtimeHealthController.dispose();
    _preferencesController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _preferencesController.load();
    await _runtimeHealthController.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final hasSmokeConfig = widget.smokeModelPath != null;
    return AnimatedBuilder(
      animation: _preferencesController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Essential',
          theme: buildEssentialTheme(),
          darkTheme: buildEssentialDarkTheme(),
          themeMode: _preferencesController.themeMode,
          home: AppLanguageScope(
            languagePack: _preferencesController.languagePack,
            child: !_preferencesController.isReady
                ? const _LaunchScreen()
                : _preferencesController.onboardingCompleted
                ? EssentialHomeScreen(
                    controller: _controller,
                    preferencesController: _preferencesController,
                    runtimeHealthController: _runtimeHealthController,
                    initialIndex: _homeIndex == 0 && hasSmokeConfig
                        ? 1
                        : _homeIndex,
                    smokeModelPath: widget.smokeModelPath,
                    smokePrompt: widget.smokePrompt,
                    smokePrompts: widget.smokePrompts,
                    smokeImagePaths: widget.smokeImagePaths,
                    smokeAudioPaths: widget.smokeAudioPaths,
                    onReplayOnboarding: () async {
                      await _preferencesController.resetOnboarding();
                      setState(() {
                        _homeIndex = 0;
                      });
                    },
                  )
                : OnboardingScreen(
                    controller: _controller,
                    onFinished: () async {
                      await _preferencesController.completeOnboarding();
                      setState(() {
                        _homeIndex = hasSmokeConfig ? 0 : _homeIndex;
                      });
                    },
                    onOpenModels: () {
                      setState(() {
                        _homeIndex = 3;
                      });
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _LaunchScreen extends StatelessWidget {
  const _LaunchScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(context).colorScheme.secondaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 36,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.appText('Essential を起動中…', 'Starting Essential...'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}
