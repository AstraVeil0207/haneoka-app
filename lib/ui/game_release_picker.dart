import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../save/game_save.dart';
import 'labels.dart';

/// Choose the release for a save file that does not identify its game version.
Future<GameRelease?> chooseGameSaveRelease(
  BuildContext context, {
  GameRelease? initial,
}) => showModalBottomSheet<GameRelease>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  builder: (context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.versionQuestion,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                t.versionHint,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final release in const [
                GameRelease.jp,
                GameRelease.intlStore,
                GameRelease.intlOfficial,
              ])
                Semantics(
                  checked: release == initial,
                  inMutuallyExclusiveGroup: true,
                  child: ListTile(
                    leading: Icon(
                      release == initial
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(release.label(t)),
                    selected: release == initial,
                    onTap: () => Navigator.pop(context, release),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t.cancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
