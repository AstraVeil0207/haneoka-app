import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../save/export.dart';
import '../save/game_save.dart';
import '../save/save_view.dart';
import '../shell/page.dart';
import 'json_view.dart';
import 'labels.dart';

/// One account: its headline numbers, every section the save holds, and exports.
class SaveScreen extends StatelessWidget {
  const SaveScreen({super.key, required this.save});
  final GameSave save;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final view = SaveView(save);
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final date = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_Hm();
    final present = view.present;
    final clears = view.clearsByDifficulty;
    final theme = Theme.of(context);

    Future<void> copyPackage() async {
      await Clipboard.setData(ClipboardData(text: exportTeamPackage(save)));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.copied)));
      }
    }

    Future<void> saveFile() async {
      final bytes = exportSave(save);
      final name =
          'our-notes-${save.release?.server ?? 'save'}-${save.profileId}.json';
      final path = await FilePicker.platform.saveFile(
        fileName: name,
        bytes: bytes,
      );
      if (path == null) return;
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        await File(path).writeAsBytes(bytes);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.saved)));
      }
    }

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    Widget fact(String label, String value) => ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(value, style: theme.textTheme.bodyLarge),
    );

    return ShellPage(
      title: save.name ?? save.profileId,
      actions: [
        BarAction(
          icon: Icons.content_copy,
          label: t.exportTeam,
          onPressed: copyPackage,
        ),
        BarAction(
          icon: Icons.save_alt,
          label: t.exportSave,
          onPressed: saveFile,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          fact(t.playerId, save.profileId),
          if (save.release != null) fact(t.release, save.release!.label(t)),
          if (save.modifiedAt != null)
            fact(t.savedAt, date.format(save.modifiedAt!.toLocal())),
          if (view.playerRank != null) fact(t.playerRank, '${view.playerRank}'),
          if (view.exp != null) fact(t.playerExp, number.format(view.exp)),
          if (view.vipRank != null) fact(t.vipRank, '${view.vipRank}'),
          if (present.containsKey(SaveSection.ratings))
            fact(t.highScoreRating, number.format(view.highScoreRating)),
          if (present.containsKey(SaveSection.songs))
            fact(
              t.clears,
              ['EASY', 'NORMAL', 'HARD', 'EXPERT'].indexed
                  .map((e) => '${e.$2} ${clears.values.elementAt(e.$1)}')
                  .join(' · '),
            ),
          const Divider(),
          for (final entry in present.entries)
            ListTile(
              title: Text(entry.key.label(t)),
              trailing: Text(
                number.format(entry.value),
                style: theme.textTheme.bodyLarge,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SectionScreen(
                    title: entry.key.label(t),
                    rows: view.rows(entry.key),
                  ),
                ),
              ),
            ),
          const Divider(),
          heading(t.allFields),
          ListTile(
            title: Text(t.settings),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openJson(context, t.settings, view.settings),
          ),
          if (view.persist.isNotEmpty)
            ListTile(
              title: Text(t.latestLive),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openJson(context, t.latestLive, view.persist),
            ),
          ListTile(
            title: Text(t.allFields),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openJson(context, t.allFields, view.player),
          ),
        ],
      ),
    );
  }

  static void _openJson(BuildContext context, String title, Object? value) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShellPage(
            title: title,
            body: JsonView(value: value),
          ),
        ),
      );
}

/// The rows of one section, each opening its full record.
class SectionScreen extends StatelessWidget {
  const SectionScreen({super.key, required this.title, required this.rows});
  final String title;
  final List<Map<String, Object?>> rows;

  /// The field that names a row, in the game's own naming.
  static const _idFields = [
    '_masterId',
    '_mLiveMusicId',
    '_mstLiveMusicId',
    '_mChallengeMusicId',
    '_masterItemId',
    '_id',
    '_eventId',
    '_spotId',
    '_slot',
    '_characterId',
    '_costumeGroupId',
    '_pair',
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return ShellPage(
      title: title,
      status: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(t.entries(rows.length)),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final idField = _idFields.firstWhere(
            row.containsKey,
            orElse: () => row.keys.first,
          );
          final scalars = row.entries
              .where(
                (e) =>
                    e.key != idField &&
                    (e.value is num || e.value is String || e.value is bool),
              )
              .take(4)
              .map((e) => '${e.key.replaceFirst('_', '')} ${e.value}')
              .join(' · ');
          return ListTile(
            title: Text('${row[idField]}'),
            subtitle: scalars.isEmpty
                ? null
                : Text(scalars, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () =>
                SaveScreen._openJson(context, '$title ${row[idField]}', row),
          );
        },
      ),
    );
  }
}
