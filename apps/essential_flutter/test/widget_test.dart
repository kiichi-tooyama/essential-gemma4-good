import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:essential_flutter/app/anonymous_telemetry_controller.dart';
import 'package:essential_flutter/app/app_language.dart';
import 'package:essential_flutter/app/app_preferences_controller.dart';
import 'package:essential_flutter/app/runtime_health_controller.dart';
import 'package:essential_flutter/features/model_management/model_management_controller.dart';
import 'package:essential_flutter/features/model_management/model_management_screen.dart';

void main() {
  testWidgets('renders model management catalog', (WidgetTester tester) async {
    final telemetryController = AnonymousTelemetryController();
    final preferencesController = AppPreferencesController();
    final runtimeHealthController = RuntimeHealthController(
      preferencesController: preferencesController,
      telemetryController: telemetryController,
    );

    await tester.pumpWidget(
      AppLanguageScope(
        languagePack: const AppLanguagePack('ja', <String, String>{}),
        child: MaterialApp(
          home: ModelManagementScreen(
            controller: ModelManagementController.preview(),
            runtimeHealthController: runtimeHealthController,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AIを追加'), findsOneWidget);
    expect(find.text('はじめる準備'), findsOneWidget);
    expect(find.text('おすすめで始める'), findsOneWidget);
    expect(find.text('チャットAI'), findsOneWidget);
    expect(find.byType(ModelManagementScreen), findsOneWidget);
  });
}
