import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

enum AppLanguagePreference { japanese, english }

class AppLanguagePack {
  const AppLanguagePack(this.code, this._strings);

  final String code;
  final Map<String, String> _strings;

  String t(String key) => _strings[key] ?? _fallback[key] ?? key;

  static const Map<String, String> _fallback = <String, String>{
    'app.title': 'Essential',
  };
}

class AppLanguageScope extends InheritedWidget {
  const AppLanguageScope({
    required this.languagePack,
    required super.child,
    super.key,
  });

  final AppLanguagePack languagePack;

  static AppLanguagePack? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppLanguageScope>()
        ?.languagePack;
  }

  @override
  bool updateShouldNotify(AppLanguageScope oldWidget) {
    return oldWidget.languagePack.code != languagePack.code;
  }
}

extension AppLanguageContext on BuildContext {
  bool get appUsesEnglish => AppLanguageScope.maybeOf(this)?.code == 'en';

  String appText(String japanese, String english) {
    return appUsesEnglish ? english : japanese;
  }
}

Future<AppLanguagePack> loadAppLanguagePack(
  AppLanguagePreference preference,
) async {
  final code = switch (preference) {
    AppLanguagePreference.japanese => 'ja',
    AppLanguagePreference.english => 'en',
  };
  final raw = await rootBundle.loadString('assets/i18n/$code.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return AppLanguagePack(
    code,
    decoded.map((key, value) => MapEntry(key, value.toString())),
  );
}
