import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Window policy belongs to the app shell; renderers only receive a viewport.
final playerOrientation = PlayerOrientationController();

class PlayerOrientationController {
  final _requests = <Object, ModalRoute<dynamic>>{};
  PageRoute<dynamic>? _route;
  bool _scheduled = false, _applied = false, _refresh = false;
  Future<void> _pending = Future<void>.value();

  void setActiveRoute(PageRoute<dynamic>? route) {
    if (_route == route) return;
    _route = route;
    if (_requests.isNotEmpty || _applied) _schedule();
  }

  void request(Object owner, ModalRoute<dynamic>? route) {
    if (route == null) {
      if (_requests.remove(owner) != null) _schedule();
    } else if (_requests[owner] != route) {
      _requests[owner] = route;
      _schedule();
    }
  }

  void refresh() {
    _refresh = true;
    _schedule();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // Route replacement releases and acquires owners in the same frame.
    // Coalescing avoids an intervening portrait request between two players.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      _pending = _pending.then((_) async {
        final landscape = _requests.values.any((route) => route == _route);
        final refresh = _refresh;
        _refresh = false;
        if (landscape == _applied && !refresh) return;
        try {
          await SystemChrome.setPreferredOrientations(
            landscape
                ? const [
                    DeviceOrientation.landscapeLeft,
                    DeviceOrientation.landscapeRight,
                  ]
                : const [],
          );
          _applied = landscape;
        } on PlatformException catch (error) {
          debugPrint('Player orientation: $error');
        } on MissingPluginException catch (error) {
          debugPrint('Player orientation: $error');
        }
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

/// Mobile players request landscape while their page is visible. The platform
/// retains its large-display and multitasking rules; desktop windows stay free.
class PlayerOrientationScope extends StatefulWidget {
  const PlayerOrientationScope({
    super.key,
    required this.landscape,
    required this.child,
  });
  final bool landscape;
  final Widget child;

  @override
  State<PlayerOrientationScope> createState() => _PlayerOrientationScopeState();
}

class _PlayerOrientationScopeState extends State<PlayerOrientationScope>
    with WidgetsBindingObserver {
  ui.FlutterView? _view;
  ModalRoute<dynamic>? _route;
  (int, double, double)? _displayMetrics;

  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.maybeOf(context);
    _route = ModalRoute.of(context);
    _sync();
  }

  @override
  void didUpdateWidget(PlayerOrientationScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.landscape != widget.landscape) _sync();
  }

  @override
  void didChangeMetrics() => _sync();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_mobile && state == AppLifecycleState.resumed) {
      _sync();
      playerOrientation.refresh();
    }
  }

  void _sync() {
    final display = _view?.display;
    final previous = _displayMetrics;
    _displayMetrics = display == null
        ? null
        : (display.id, display.size.shortestSide, display.devicePixelRatio);
    playerOrientation.request(
      this,
      _mobile && widget.landscape ? _route : null,
    );
    // Rotation and the keyboard keep this identity stable. Folding or moving
    // to another display can change whether the system honors orientation.
    if (_mobile &&
        widget.landscape &&
        previous != null &&
        previous != _displayMetrics) {
      playerOrientation.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    playerOrientation.request(this, null);
    _view = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
