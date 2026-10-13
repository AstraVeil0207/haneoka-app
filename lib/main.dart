import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'core/app_state.dart';
import 'l10n/app_localizations.dart';
import 'shell/shell.dart';
import 'ui/theme.dart';
import 'team_builder/engine_client.dart'
    show runTeamEngineHost, runTeamEngineProcess;

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty &&
      arguments.first.startsWith('--haneoka-team-engine-process=')) {
    await runTeamEngineProcess(
      arguments.first.substring('--haneoka-team-engine-process='.length),
    );
    return;
  }
  if (arguments.isNotEmpty &&
      arguments.first.startsWith('--haneoka-team-engine=')) {
    await runTeamEngineHost(
      arguments.first.substring('--haneoka-team-engine='.length),
    );
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final state = await AppState.load(
    WidgetsBinding.instance.platformDispatcher.locale,
  );
  Uri? initialAddress;
  for (final argument in arguments) {
    if (argument.startsWith('-')) continue;
    final uri = Uri.tryParse(argument);
    if (uri != null &&
        const {'https', 'http', 'file', 'haneoka'}.contains(uri.scheme)) {
      initialAddress = uri;
      break;
    }
    if (FileSystemEntity.typeSync(argument) != FileSystemEntityType.notFound) {
      initialAddress = Uri.file(argument, windows: Platform.isWindows);
      break;
    }
  }
  runApp(
    AppScope(
      state: state,
      child: HaneokaApp(initialAddress: initialAddress),
    ),
  );
}

class HaneokaApp extends StatelessWidget {
  const HaneokaApp({super.key, this.initialAddress});
  final Uri? initialAddress;

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
      home: AppShell(initialAddress: initialAddress),
    );
  }
}
