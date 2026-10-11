import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'ui/import_screen.dart';
import 'ui/theme.dart';

void main() => runApp(const HaneokaApp());

class HaneokaApp extends StatelessWidget {
  const HaneokaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: haneokaTheme(Brightness.light),
        darkTheme: haneokaTheme(Brightness.dark),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ImportScreen(),
      );
}
