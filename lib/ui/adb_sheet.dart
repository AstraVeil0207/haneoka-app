import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../core/app_state.dart';
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
  bool _refreshing = false;
  Object? _error;
  Timer? _poll;

  AppLocalizations get t => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _adb != null && !_refreshing) unawaited(_refresh());
    });
    AdbSaveSource.locate().then((path) {
      if (!mounted) return;
      if (path == null) {
        setState(() => _missing = true);
      } else {
        _use(path);
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _use(String path) async {
    if (!mounted) return;
    setState(() {
      _adb = AdbSaveSource(path);
      _missing = false;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing || _adb == null || !mounted) return;
    _refreshing = true;
    try {
      final devices = await _adb!.devices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _devices = const [];
          _error = error;
        });
      }
    } finally {
      _refreshing = false;
    }
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
    final pairAddress = address.text.trim(),
        pairCode = code.text.trim(),
        connectAddress = connect.text.trim();
    address.dispose();
    code.dispose();
    connect.dispose();
    if (ok != true || !mounted) return;
    final validAddress = RegExp(
      r'^(?:\[[0-9a-fA-F:]+\]|[A-Za-z0-9.-]+):[0-9]{1,5}$',
    );
    if (!validAddress.hasMatch(pairAddress) ||
        !RegExp(r'^\d{6}$').hasMatch(pairCode) ||
        (connectAddress.isNotEmpty && !validAddress.hasMatch(connectAddress))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppScope.of(context).text(
              'app.import.pairFormat',
              'Enter IP:port and a six-digit pairing code.',
            ),
          ),
        ),
      );
      return;
    }
    bool paired;
    try {
      paired = await _adb!.pair(pairAddress, pairCode);
      if (paired && connectAddress.isNotEmpty) {
        await _adb!.connect(connectAddress);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }
    if (paired && connectAddress.isNotEmpty) {
      // The wireless connection is already established above.
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
    final List<GameRelease> installed;
    try {
      installed = await adb.installed(device.serial);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }
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
                    icon: const Icon(Symbols.wifi_rounded),
                  ),
                if (_adb != null)
                  IconButton(
                    tooltip: t.refresh,
                    onPressed: _refresh,
                    icon: const Icon(Symbols.refresh_rounded),
                  ),
              ],
            ),
          ),
          if (_missing) ...[
            ListTile(
              leading: const Icon(Symbols.error_rounded),
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
          ] else if (_error != null)
            ListTile(
              leading: const Icon(Symbols.error_rounded),
              title: Text(
                AppScope.of(context).text(
                  'app.import.adbFailed',
                  'Could not read devices. Check debugging authorization and reconnect.',
                ),
              ),
              subtitle: Text('$_error'),
            )
          else if (devices == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (devices.isEmpty)
            ListTile(
              leading: const Icon(Symbols.usb_off_rounded),
              title: Text(t.noDevices),
            )
          else
            for (final device in devices)
              ListTile(
                leading: Icon(
                  device.ready
                      ? Symbols.smartphone_rounded
                      : Symbols.lock_rounded,
                ),
                title: Text(
                  device.model?.replaceAll('_', ' ') ?? device.serial,
                ),
                subtitle: device.ready
                    ? Text(device.serial)
                    : Text(
                        device.state == 'offline'
                            ? AppScope.of(context).text(
                                'app.import.deviceOffline',
                                'Device offline. Reconnect it and allow USB debugging.',
                              )
                            : t.deviceUnauthorized,
                      ),
                enabled: device.ready,
                onTap: () => _read(device),
              ),
          if (Platform.isWindows)
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://developer.android.com/studio/run/oem-usb'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Symbols.open_in_new_rounded),
              label: Text(
                AppScope.of(context)
                    .text('app.import.usbDriverGuide', 'USB driver guide'),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
