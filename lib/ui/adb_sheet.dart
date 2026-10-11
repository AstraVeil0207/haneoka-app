import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../save/game_save.dart';
import '../sources/adb.dart';

typedef SaveRead = Future<void> Function(
  Future<void> Function(SaveCollector collector) read,
);

Future<void> showAdbSheet(BuildContext context, {required SaveRead onRead}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AdbSheet(onRead: onRead),
    );

/// Connected phones, wireless pairing, and the game releases on the chosen phone.
class _AdbSheet extends StatefulWidget {
  const _AdbSheet({required this.onRead});
  final SaveRead onRead;
  @override
  State<_AdbSheet> createState() => _AdbSheetState();
}

class _AdbSheetState extends State<_AdbSheet> {
  AdbSaveSource? _adb;
  List<AdbDevice>? _devices;
  bool _missing = false;

  AppLocalizations get t => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    AdbSaveSource.locate().then(
      (path) => path == null ? setState(() => _missing = true) : _use(path),
    );
  }

  Future<void> _use(String path) async {
    setState(() {
      _adb = AdbSaveSource(path);
      _missing = false;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final devices = await _adb!.devices().catchError((_) => <AdbDevice>[]);
    if (mounted) setState(() => _devices = devices);
  }

  Future<void> _chooseAdb() async {
    final picked = await FilePicker.platform.pickFiles();
    final path = picked?.files.single.path;
    if (path != null) await _use(path);
  }

  Future<void> _pair() async {
    final address = TextEditingController(),
        code = TextEditingController(),
        connect = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.pairWireless),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: address,
              decoration: InputDecoration(labelText: t.pairAddress),
            ),
            TextField(
              controller: code,
              decoration: InputDecoration(labelText: t.pairCode),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: connect,
              decoration: InputDecoration(labelText: t.connectAddress),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.pairWireless),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final paired = await _adb!.pair(address.text.trim(), code.text.trim());
    if (paired && connect.text.trim().isNotEmpty) {
      await _adb!.connect(connect.text.trim());
    }
    if (!mounted) return;
    if (!paired) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.pairFailed)));
    }
    await _refresh();
  }

  Future<void> _read(AdbDevice device) async {
    final adb = _adb!;
    final installed = await adb.installed(device.serial);
    if (!mounted) return;
    if (installed.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.gameNotInstalled)));
      return;
    }
    Navigator.pop(context);
    await widget.onRead((collector) async {
      for (final release in installed) {
        await adb.scan(device.serial, release, collector);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              t.devices,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_adb != null)
                  IconButton(
                    tooltip: t.pairWireless,
                    onPressed: _pair,
                    icon: const Icon(Icons.wifi),
                  ),
                if (_adb != null)
                  IconButton(
                    tooltip: t.refresh,
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
          ),
          if (_missing) ...[
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(t.adbMissing),
            ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(
                      'https://developer.android.com/tools/releases/platform-tools',
                    ),
                  ),
                  child: Text(t.getPlatformTools),
                ),
                TextButton(onPressed: _chooseAdb, child: Text(t.chooseAdb)),
              ],
            ),
          ] else if (devices == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (devices.isEmpty)
            ListTile(
              leading: const Icon(Icons.usb_off),
              title: Text(t.noDevices),
            )
          else
            for (final device in devices)
              ListTile(
                leading: Icon(
                  device.ready ? Icons.smartphone : Icons.lock_outline,
                ),
                title: Text(
                  device.model?.replaceAll('_', ' ') ?? device.serial,
                ),
                subtitle: device.ready
                    ? Text(device.serial)
                    : Text(t.deviceUnauthorized),
                enabled: device.ready,
                onTap: () => _read(device),
              ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
