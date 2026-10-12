import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/app_updates.dart';

Future<void> showAppUpdate(BuildContext context, AppRelease release) =>
    showDialog<void>(
      context: context,
      builder: (context) {
        final t = AppScope.of(context).text;
        return AlertDialog(
          title: Text(
            t('app.updates.available', 'Update available: {version}', {
              'version': release.version,
            }),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: SelectableText(release.notes)),
          ),
          actions: [
            TextButton(
              onPressed: () {
                AppUpdates.instance.dismiss();
                Navigator.of(context).pop();
              },
              child: Text(t('app.updates.later', 'Later')),
            ),
            TextButton(
              onPressed: () => _open(context, release.url),
              child: Text(t('app.updates.releaseNotes', 'Release notes')),
            ),
            if (release.download != null)
              FilledButton.icon(
                onPressed: () => _open(context, release.download!),
                icon: const Icon(Symbols.download_rounded),
                label: Text(t('app.updates.download', 'Download update')),
              ),
          ],
        );
      },
    );

Future<void> _open(BuildContext context, Uri url) async {
  final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppScope.of(
            context,
          ).text('app.updates.openFailed', 'Could not open the download link.'),
        ),
      ),
    );
  }
}

class AppUpdateSettings extends StatelessWidget {
  const AppUpdateSettings({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppUpdates.instance,
    builder: (context, _) {
      final updates = AppUpdates.instance;
      final t = AppScope.of(context).text;
      return Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Symbols.system_update_rounded),
            contentPadding: EdgeInsets.zero,
            title: Text(
              t('app.updates.automatic', 'Automatically check for updates'),
            ),
            subtitle: Text(
              t(
                'app.updates.frequency',
                'Check once a day when the app opens.',
              ),
            ),
            value: updates.automatic,
            onChanged: updates.setAutomatic,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(t('app.updates.check', 'Check for updates')),
            subtitle: updates.checking
                ? Text(t('app.updates.checking', 'Checking…'))
                : updates.error != null
                ? Text(
                    t(
                      'app.updates.failed',
                      'Could not check for updates. Try again.',
                    ),
                  )
                : updates.available != null
                ? Text(
                    t('app.updates.available', 'Update available: {version}', {
                      'version': updates.available!.version,
                    }),
                  )
                : updates.checked
                ? Text(
                    t('app.updates.upToDate', 'You have the latest version.'),
                  )
                : null,
            trailing: updates.checking
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.refresh_rounded),
            onTap: updates.checking
                ? null
                : () async {
                    await updates.check(manual: true);
                    if (context.mounted && updates.available != null) {
                      await showAppUpdate(context, updates.available!);
                    }
                  },
          ),
        ],
      );
    },
  );
}
