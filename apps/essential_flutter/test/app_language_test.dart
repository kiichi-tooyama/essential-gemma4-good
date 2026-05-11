import 'package:essential_flutter/app/app_language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('appText follows the active language scope', (tester) async {
    await tester.pumpWidget(
      const AppLanguageScope(
        languagePack: AppLanguagePack('ja', <String, String>{}),
        child: MaterialApp(home: _LanguageProbe()),
      ),
    );
    expect(find.text('日本語'), findsOneWidget);

    await tester.pumpWidget(
      const AppLanguageScope(
        languagePack: AppLanguagePack('en', <String, String>{}),
        child: MaterialApp(home: _LanguageProbe()),
      ),
    );
    expect(find.text('English'), findsOneWidget);
  });
}

class _LanguageProbe extends StatelessWidget {
  const _LanguageProbe();

  @override
  Widget build(BuildContext context) {
    return Text(context.appText('日本語', 'English'));
  }
}
