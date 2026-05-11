import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'app_language.dart';

enum AppThemePreference { system, light, dark }

class AppPreferencesController extends ChangeNotifier {
  bool _isReady = false;
  bool _onboardingCompleted = false;
  AppThemePreference _themePreference = AppThemePreference.system;
  AppLanguagePreference _languagePreference = AppLanguagePreference.english;
  AppLanguagePack _languagePack = const AppLanguagePack(
    'en',
    <String, String>{},
  );
  bool _telemetryEnabled = false;
  bool _locationSearchEnabled = true;
  bool _recoveredFromUnexpectedExit = false;
  bool _inferenceActive = false;
  File? _preferencesFile;

  bool get isReady => _isReady;

  bool get onboardingCompleted => _onboardingCompleted;

  AppThemePreference get themePreference => _themePreference;

  AppLanguagePreference get languagePreference => _languagePreference;

  bool get useEnglish => _languagePreference == AppLanguagePreference.english;

  AppLanguagePack get languagePack => _languagePack;

  String t(String key) => _languagePack.t(key);

  bool get telemetryEnabled => _telemetryEnabled;

  bool get locationSearchEnabled => _locationSearchEnabled;

  bool get recoveredFromUnexpectedExit => _recoveredFromUnexpectedExit;

  ThemeMode get themeMode {
    return switch (_themePreference) {
      AppThemePreference.system => ThemeMode.system,
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
    };
  }

  Future<void> load() async {
    if (_isReady) {
      return;
    }

    final directory = await getApplicationSupportDirectory();
    _preferencesFile = File(
      path.join(directory.path, 'essential_app_preferences.json'),
    );

    if (await _preferencesFile!.exists()) {
      final payload =
          jsonDecode(await _preferencesFile!.readAsString())
              as Map<String, dynamic>;
      _onboardingCompleted = payload['onboarding_completed'] as bool? ?? false;
      _themePreference = _themePreferenceFromString(
        payload['theme_preference'] as String?,
      );
      _languagePreference = _languagePreferenceFromString(
        payload['language_preference'] as String?,
      );
      _telemetryEnabled = payload['telemetry_enabled'] as bool? ?? false;
      _locationSearchEnabled =
          payload['location_search_enabled'] as bool? ?? true;
      _inferenceActive = payload['inference_active'] as bool? ?? false;
      if (_inferenceActive) {
        _recoveredFromUnexpectedExit = true;
        _inferenceActive = false;
        await _persist();
      }
    }
    _languagePack = await loadAppLanguagePack(_languagePreference);

    _isReady = true;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    _onboardingCompleted = true;
    notifyListeners();
    await _persist();
  }

  Future<void> resetOnboarding() async {
    _onboardingCompleted = false;
    notifyListeners();
    await _persist();
  }

  Future<void> updateThemePreference(AppThemePreference preference) async {
    if (_themePreference == preference) {
      return;
    }
    _themePreference = preference;
    notifyListeners();
    await _persist();
  }

  Future<void> updateLanguagePreference(
    AppLanguagePreference preference,
  ) async {
    final nextPreference = AppLanguagePreference.english;
    if (_languagePreference == nextPreference) {
      return;
    }
    _languagePreference = nextPreference;
    _languagePack = await loadAppLanguagePack(nextPreference);
    notifyListeners();
    await _persist();
  }

  Future<void> updateTelemetryEnabled(bool enabled) async {
    if (_telemetryEnabled == enabled) {
      return;
    }
    _telemetryEnabled = enabled;
    notifyListeners();
    await _persist();
  }

  Future<void> updateLocationSearchEnabled(bool enabled) async {
    if (_locationSearchEnabled == enabled) {
      return;
    }
    _locationSearchEnabled = enabled;
    notifyListeners();
    await _persist();
  }

  Future<void> markInferenceStarted() async {
    if (_inferenceActive) {
      return;
    }
    _inferenceActive = true;
    await _persist();
  }

  Future<void> markInferenceFinished() async {
    if (!_inferenceActive) {
      return;
    }
    _inferenceActive = false;
    await _persist();
  }

  Future<void> consumeRecoveredInferenceNotice() async {
    if (!_recoveredFromUnexpectedExit) {
      return;
    }
    _recoveredFromUnexpectedExit = false;
    notifyListeners();
    await _persist();
  }

  AppThemePreference _themePreferenceFromString(String? rawValue) {
    return switch (rawValue) {
      'light' => AppThemePreference.light,
      'dark' => AppThemePreference.dark,
      _ => AppThemePreference.system,
    };
  }

  AppLanguagePreference _languagePreferenceFromString(String? rawValue) {
    return switch (rawValue) {
      'ja' => AppLanguagePreference.english,
      'en' => AppLanguagePreference.english,
      _ => AppLanguagePreference.english,
    };
  }

  String _themePreferenceToString(AppThemePreference preference) {
    return switch (preference) {
      AppThemePreference.system => 'system',
      AppThemePreference.light => 'light',
      AppThemePreference.dark => 'dark',
    };
  }

  String _languagePreferenceToString(AppLanguagePreference preference) {
    return switch (preference) {
      AppLanguagePreference.japanese => 'ja',
      AppLanguagePreference.english => 'en',
    };
  }

  Future<void> _persist() async {
    final file = _preferencesFile;
    if (file == null) {
      return;
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'onboarding_completed': _onboardingCompleted,
        'theme_preference': _themePreferenceToString(_themePreference),
        'language_preference': _languagePreferenceToString(_languagePreference),
        'telemetry_enabled': _telemetryEnabled,
        'location_search_enabled': _locationSearchEnabled,
        'inference_active': _inferenceActive,
      }),
    );
  }
}
