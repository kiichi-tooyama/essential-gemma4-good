import 'package:essential_flutter/features/model_management/model_management_controller.dart';
import 'package:essential_flutter/features/model_management/model_management_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'download every catalog model and bundle',
    (tester) async {
      final controller = ModelManagementController.createDefault();
      await controller.initialize();

      debugPrint(
        'ESSENTIAL_DOWNLOAD_CATALOG models=${controller.catalog.length} '
        'bundles=${controller.bundles.length} adapters=${controller.adapters.length}',
      );
      for (final entry in controller.catalog) {
        debugPrint(
          'ESSENTIAL_DOWNLOAD_MODEL_CATALOG id=${entry.modelId} '
          'runtime=${entry.runtime} mb=${entry.downloadSizeMb}',
        );
      }
      for (final bundle in controller.bundles) {
        debugPrint(
          'ESSENTIAL_DOWNLOAD_BUNDLE_CATALOG id=${bundle.bundleId} '
          'profiles=${bundle.taskProfiles.join(",")} mb=${bundle.downloadSizeMb}',
        );
      }

      await controller.downloadEverything();
      await controller.refreshCatalog();

      final missingModels = <String>[];
      for (final entry in controller.catalog) {
        final direct = controller.installationFor(entry.modelId);
        final component = controller.componentInstallationFor(entry.modelId);
        final state = controller.stateFor(entry);
        debugPrint(
          'ESSENTIAL_DOWNLOAD_MODEL_STATE id=${entry.modelId} '
          'state=${state.name} direct=${direct != null} component=${component != null} '
          'error=${controller.errorFor(entry.modelId) ?? ""}',
        );
        if (state != ModelAvailabilityState.available) {
          missingModels.add(entry.modelId);
        }
      }

      final missingBundles = <String>[];
      for (final bundle in controller.bundles) {
        final installed = controller.bundleInstallationFor(bundle.bundleId);
        debugPrint(
          'ESSENTIAL_DOWNLOAD_BUNDLE_STATE id=${bundle.bundleId} '
          'installed=${installed != null} error=${controller.bundleErrorFor(bundle.bundleId) ?? ""}',
        );
        if (installed == null) {
          missingBundles.add(bundle.bundleId);
        }
      }

      debugPrint(
        'ESSENTIAL_DOWNLOAD_STORAGE used=${controller.storageSnapshot.usedBytes} '
        'quota=${controller.storageSnapshot.quotaBytes} installed=${controller.storageSnapshot.installedCount} '
        'components=${controller.storageSnapshot.sharedComponentCount}',
      );
      debugPrint(
        'ESSENTIAL_DOWNLOAD_DONE missingModels=${missingModels.join(",")} '
        'missingBundles=${missingBundles.join(",")}',
      );

      expect(missingModels, isEmpty);
      expect(missingBundles, isEmpty);
    },
    timeout: const Timeout(Duration(hours: 3)),
  );
}
