import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'core/app_state.dart';
import 'l10n/app_localizations.dart';
import 'shell/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final state = await AppState.load(
    WidgetsBinding.instance.platformDispatcher.locale,
  );
  runApp(AppScope(state: state, child: const HaneokaApp()));
}

class HaneokaApp extends StatelessWidget {
  const HaneokaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return MaterialApp(
      title: 'Haneoka',
      locale: state.locale,
      theme: haneokaTheme(
        Brightness.light,
        seed: state.seed,
        compact: state.compact,
      ),
      darkTheme: haneokaTheme(
        Brightness.dark,
        seed: state.seed,
        compact: state.compact,
      ),
      themeMode: state.themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AppShell(),
    );
  }
}
