import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../l10n/app_localizations.dart';
import '../save/game_save.dart';
import '../sources/android.dart';
import '../sources/files.dart';
import '../shell/page.dart';
import 'adb_sheet.dart';
import 'backup_sheet.dart';
import 'labels.dart';
import 'save_screen.dart';

/// Every way this platform can reach the game's save, then the accounts found.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final List<GameSave> _saves = [];
  bool _busy = false;
  ShizukuStatus? _shizuku;
  bool _canGrant = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _refreshAndroid();
  }

  Future<void> _refreshAndroid() async {
    final status = await AndroidSaveSource.shizukuStatus();
    final grant = await AndroidSaveSource.canGrantGameFolder();
    if (!mounted) return;
    setState(() {
      _shizuku = status;
      _canGrant = grant;
    });
  }

  AppLocalizations get t => AppLocalizations.of(context);

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Runs one import and adds what it found; a run that finds nothing says so.
  Future<void> _run(Future<void> Function(SaveCollector collector) read) async {
    setState(() => _busy = true);
    final collector = SaveCollector();
    try {
      await read(collector);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (collector.saves.isEmpty) {
      _say(t.noSaves);
      return;
    }
    setState(() {
      for (final save in collector.saves) {
        _saves.removeWhere(
          (s) => s.profileId == save.profileId && s.release == save.release,
        );
        _saves.insert(0, save);
      }
    });
    if (collector.saves.length == 1) _open(collector.saves.single);
  }

  void _open(GameSave save) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => SaveScreen(save: save)));

  Future<GameRelease?> _pickRelease() => showModalBottomSheet<GameRelease>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final release in GameRelease.values)
            ListTile(
              title: Text(release.label(t)),
              onTap: () => Navigator.pop(context, release),
            ),
        ],
      ),
    ),
  );

  Future<void> _readShizuku() async {
    var status = await AndroidSaveSource.shizukuStatus();
    if (status == ShizukuStatus.needsPermission &&
        await AndroidSaveSource.requestShizuku()) {
      status = ShizukuStatus.ready;
    }
    setState(() => _shizuku = status);
    if (status != ShizukuStatus.ready) {
      if (status == ShizukuStatus.notRunning) {
        await AndroidSaveSource.openShizuku();
      }
      return;
    }
    await _run((collector) async {
      for (final release in GameRelease.values) {
        await AndroidSaveSource.readWithShizuku(release, collector);
      }
    });
  }

  Future<void> _grantFolder() async {
    final release = await _pickRelease();
    if (release == null) return;
    final uri = await AndroidSaveSource.grantGameFolder(release);
    if (uri == null) return;
    await _run(
      (collector) =>
          AndroidSaveSource.readFolder(uri, collector, release: release),
    );
  }

  Future<void> _readGranted() => _run((collector) async {
    for (final uri in await AndroidSaveSource.grantedFolders()) {
      await AndroidSaveSource.readFolder(uri, collector);
    }
  });

  Future<void> _pickFiles({bool folder = false}) async {
    final release = await _pickRelease();
    if (release == null) return;
    if (folder) {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null) return;
      await _run(
        (collector) =>
            FileSaveSource(collector, release: release).addPath(path),
      );
      return;
    }
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: !_hasPaths,
    );
    if (picked == null) return;
    await _run((collector) async {
      final source = FileSaveSource(collector, release: release);
      for (final file in picked.files) {
        if (_hasPaths && file.path != null) {
          await source.addPath(file.path!);
        } else if (file.bytes != null) {
          source.addBytes(file.bytes!, file.name);
        }
      }
    });
  }

  static bool get _hasPaths => !Platform.isIOS;
  static bool get _desktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final methods = <Widget>[
      if (Platform.isAndroid) ...[
        ListTile(
          leading: const Icon(Symbols.adb_rounded),
          title: Text(t.sourceShizuku),
          subtitle: switch (_shizuku) {
            ShizukuStatus.notRunning => Text(t.shizukuNotRunning),
            ShizukuStatus.unsupported => Text(t.shizukuUnsupported),
            _ => null,
          },
          trailing: _shizuku == ShizukuStatus.notRunning
              ? TextButton(
                  onPressed: AndroidSaveSource.openShizuku,
                  child: Text(t.openShizuku),
                )
              : null,
          onTap: _busy ? null : _readShizuku,
        ),
        if (_canGrant)
          ListTile(
            leading: const Icon(Symbols.folder_special_rounded),
            title: Text(t.sourceGrantFolder),
            trailing: IconButton(
              tooltip: t.refresh,
              onPressed: _busy ? null : _readGranted,
              icon: const Icon(Symbols.refresh_rounded),
            ),
            onTap: _busy ? null : _grantFolder,
          ),
      ],
      if (_desktop) ...[
        ListTile(
          leading: const Icon(Symbols.phone_android_rounded),
          title: Text(t.sourceAdb),
          onTap: _busy ? null : () => showAdbSheet(context, onRead: _run),
        ),
        ListTile(
          leading: const Icon(Symbols.phone_iphone_rounded),
          title: Text(t.sourceIosBackup),
          onTap: _busy ? null : () => showBackupSheet(context, onRead: _run),
        ),
      ],
      ListTile(
        leading: const Icon(Symbols.file_open_rounded),
        title: Text(t.sourceFiles),
        trailing: _hasPaths
            ? IconButton(
                tooltip: t.sourceFiles,
                onPressed: _busy ? null : () => _pickFiles(folder: true),
                icon: const Icon(Symbols.folder_open_rounded),
              )
            : null,
        onTap: _busy ? null : _pickFiles,
      ),
    ];
    return ShellPage(
      title: t.importTitle,
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (_busy) const LinearProgressIndicator(),
          ...methods,
          if (_saves.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                t.accounts,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            for (final save in _saves)
              ListTile(
                leading: const Icon(Symbols.person_rounded),
                title: Text(save.name ?? save.profileId),
                subtitle: Text(
                  [
                    save.release?.label(t),
                    save.profileId,
                  ].whereType<String>().join(' · '),
                ),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => _open(save),
              ),
          ],
        ],
      ),
    );
  }
}
