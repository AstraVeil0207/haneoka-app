import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../core/app_updates.dart';

class DistributionSettings extends StatelessWidget {
  const DistributionSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Symbols.install_desktop_rounded),
          title: Text(
            t('app.distribution.title', 'Installers and installation guides'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        Text(
          t(
            'app.distribution.available',
            'The release page lists the files actually published for each system and architecture.',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(appReleasesUrl),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Symbols.download_rounded),
              label: Text(t('app.distribution.downloads', 'All downloads')),
            ),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(
                  'https://github.com/haneoka-gakuen/haneoka-app#download-and-installation',
                ),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Symbols.description_rounded),
              label: Text(t('app.distribution.guide', 'Installation guide')),
            ),
            if (Platform.isIOS) ...[
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(
                      text: 'https://github.com/haneoka-gakuen/haneoka-app/releases/latest/download/altstore-source.json',
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          t(
                            'app.distribution.sourceCopied',
                            'Source URL copied. Add it in AltStore Classic or SideStore after release 0.1.0 is published.',
                          ),
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Symbols.content_copy_rounded),
                label: Text(
                  t(
                    'app.distribution.copySource',
                    'Copy AltStore / SideStore source URL',
                  ),
                ),
              ),
              for (final (name, url) in const [
                ('AltStore Classic', 'https://altstore.io/'),
                ('SideStore', 'https://sidestore.io/'),
                ('Sideloadly', 'https://sideloadly.io/'),
                ('TrollStore', 'https://github.com/opa334/TrollStore'),
              ])
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Symbols.open_in_new_rounded),
                  label: Text(name),
                ),
            ],
          ],
        ),
      ],
    );
  }
}
