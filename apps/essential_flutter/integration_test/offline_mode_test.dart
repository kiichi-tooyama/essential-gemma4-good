import 'package:essential_flutter/features/shared/web_research_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'offline web research skips web and location context',
    (tester) async {
      const connectivityChannel = MethodChannel('essential/connectivity');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        connectivityChannel,
        (call) async => call.method == 'isOnline' ? false : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          connectivityChannel,
          null,
        ),
      );

      final result = await WebResearchService().research(
        'today Tokyo weather latest',
        locationContext: 'Tokyo Station, Japan',
        locationNotice: 'location should be skipped while offline',
      );
      debugPrint(
        'ESSENTIAL_OFFLINE_RESEARCH_RESULT sources=${result.sources.length} '
        'locationContext="${result.locationContext}" '
        'notice="${result.locationNotice}"',
      );

      expect(result.sources, isEmpty);
      expect(result.locationContext, isEmpty);
      expect(result.locationNotice, contains('オフライン'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
