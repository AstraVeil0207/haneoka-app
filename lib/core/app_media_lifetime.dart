import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse, AppExitType;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'media_lifecycle.dart';

/// The application closes asynchronous media IO before its Flutter engine.
class AppMediaLifetime extends StatefulWidget {
  const AppMediaLifetime({super.key, required this.child});
  final Widget child;

  @override
  State<AppMediaLifetime> createState() => _AppMediaLifetimeState();
}

class _AppMediaLifetimeState extends State<AppMediaLifetime>
    with WidgetsBindingObserver, WindowListener {
  bool _desktopListener = false, _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      unawaited(_observeDesktopClose());
    }
  }

  Future<void> _observeDesktopClose() async {
    await windowManager.ensureInitialized();
    if (!mounted) return;
    windowManager.addListener(this);
    _desktopListener = true;
    await windowManager.setPreventClose(true);
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await MediaLifecycle.drain();
    return AppExitResponse.exit;
  }

  @override
  void onWindowClose() {
    if (_closing) return;
    _closing = true;
    unawaited(_closeDesktop());
  }

  Future<void> _closeDesktop() async {
    await MediaLifecycle.drain();
    debugPrint(
      'HANEOKA_MEDIA_EXIT_DRAINED owners=${MediaLifecycle.ownerCount}',
    );
    if (!mounted) return;
    if (Platform.isLinux) {
      // GTK window destruction during a platform-channel callback tears down
      // FlView while its task runner is still dispatching. Let the embedder
      // finish the callback and quit its application loop instead.
      await ServicesBinding.instance.exitApplication(AppExitType.required);
      return;
    }
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_desktopListener) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
