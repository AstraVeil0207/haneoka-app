import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';

import '../core/app_state.dart';

class PlaybackStageScope extends InheritedWidget {
  const PlaybackStageScope({
    super.key,
    required this.fullscreen,
    required this.epoch,
    required this.isCurrent,
    this.toggleFullscreen,
    this.setControlsExpanded,
    required super.child,
  });
  final bool fullscreen;
  final int epoch;
  final bool Function() isCurrent;
  final VoidCallback? toggleFullscreen;
  final ValueChanged<bool>? setControlsExpanded;
  static PlaybackStageScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackStageScope>();
  @override
  bool updateShouldNotify(PlaybackStageScope old) =>
      old.fullscreen != fullscreen || old.epoch != epoch;
}

/// Shared page transport. Its caller owns rendering and audio; fullscreen
/// moves the same presentation into an overlay without creating a new player.
class PlaybackPane extends StatefulWidget {
  const PlaybackPane({
    super.key,
    required this.stage,
    required this.playing,
    required this.position,
    required this.maximum,
    required this.onToggle,
    this.onSeek,
    this.onPreviewSeek,
    this.onScrubStart,
    this.onSettings,
    this.onLoop,
    this.loop = false,
    this.collapsed = false,
    this.onCollapsed,
    this.positionLabel,
    this.maximumLabel,
    this.onStageActivate,
    this.onPause,
    this.leadLabel,
    this.leadActive,
    this.leadReplay = false,
    this.controlsVisible = true,
    this.busy = false,
  });
  final WidgetBuilder stage;
  final bool playing, loop, collapsed;
  final bool? leadActive;
  final bool leadReplay, controlsVisible;
  final bool busy;
  final String? leadLabel;
  final double position, maximum;
  final String? positionLabel, maximumLabel;
  final VoidCallback? onToggle,
      onScrubStart,
      onSettings,
      onLoop,
      onStageActivate,
      onPause;
  final ValueChanged<double>? onSeek, onPreviewSeek;
  final ValueChanged<bool>? onCollapsed;
  @override
  State<PlaybackPane> createState() => _PlaybackPaneState();
}

class _PlaybackPaneState extends State<PlaybackPane> {
  OverlayEntry? _overlay;
  bool _collapsed = false, _hidden = false, _busy = false;
  double? _scrub;
  Timer? _hide;
  bool _previousFullscreen = false;
  bool _disposing = false;
  int _presentationEpoch = 0;
  bool _overlayBuildScheduled = false;
  bool get _uiAlive => mounted && !_disposing;
  bool get _desktop =>
      !kIsWeb &&
      const {
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);
  bool get _mobile =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);
  @override
  void initState() {
    super.initState();
    _collapsed = widget.collapsed;
  }

  @override
  void didUpdateWidget(PlaybackPane old) {
    super.didUpdateWidget(old);
    if (old.collapsed != widget.collapsed) _collapsed = widget.collapsed;
    _queueOverlayBuild();
    if (old.playing != widget.playing) _scheduleHide();
  }

  void _changed() {
    if (!_uiAlive) return;
    setState(() {});
    _queueOverlayBuild();
  }

  void _queueOverlayBuild() {
    if (!_uiAlive || _overlay == null || _overlayBuildScheduled) return;
    _overlayBuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayBuildScheduled = false;
      if (_uiAlive) _overlay?.markNeedsBuild();
    });
  }

  void _showControls() {
    if (!_uiAlive) return;
    _hidden = false;
    _scheduleHide();
    _changed();
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (_overlay != null && widget.playing && !_collapsed && _scrub == null) {
      _hide = Timer(const Duration(seconds: 3), () {
        if (_uiAlive && _overlay != null && widget.playing && _scrub == null) {
          _hidden = true;
          _changed();
        }
      });
    }
  }

  Future<void> _fullscreen() async {
    if (_busy || !_uiAlive) return;
    _busy = true;
    try {
      if (_overlay != null) {
        await _exitFullscreen();
        return;
      }
      if (_desktop) {
        await windowManager.ensureInitialized();
        if (!_uiAlive) return;
        _previousFullscreen = await windowManager.isFullScreen();
        if (!_uiAlive) return;
        await windowManager.setFullScreen(true);
      } else if (_mobile) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
      if (!mounted || _disposing) {
        await _exitFullscreen();
        return;
      }
      ++_presentationEpoch;
      _overlay = OverlayEntry(
        builder: (context) => Material(
          color: Colors.black,
          child: _presentation(context, fullscreen: true),
        ),
      );
      Overlay.of(context, rootOverlay: true).insert(_overlay!);
      _showControls();
    } finally {
      _busy = false;
    }
  }

  Future<void> _exitFullscreen() async {
    _hide?.cancel();
    final overlay = _overlay;
    _overlay = null;
    ++_presentationEpoch;
    overlay?.remove();
    overlay?.dispose();
    _hidden = false;
    if (_uiAlive) setState(() {});
    if (_desktop) {
      await windowManager.setFullScreen(_previousFullscreen);
    } else if (_mobile) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _hide?.cancel();
    if (_overlay != null) unawaited(_exitFullscreen());
    super.dispose();
  }

  String _clock(double seconds) {
    final value = seconds.isFinite ? seconds.round().clamp(0, 8640000) : 0;
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }

  Widget _button(
    IconData icon,
    String label,
    VoidCallback? callback, {
    bool? selected,
  }) => IconButton(
    tooltip: label,
    isSelected: selected,
    onPressed: callback,
    icon: Icon(icon, size: 20),
  );

  Widget _controls(BuildContext context, bool fullscreen) {
    final t = AppScope.of(context).text;
    if (_collapsed || _hidden) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final value = (_scrub ?? widget.position).clamp(
      0.0,
      widget.maximum > 0 ? widget.maximum : 1.0,
    );
    return Material(
      color: fullscreen
          ? scheme.surfaceContainer.withValues(alpha: .94)
          : scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 500;
            final extras = <Widget>[
              if (widget.onSettings != null)
                _button(
                  Symbols.tune_rounded,
                  t('media.chartPlayer.settings', 'Settings'),
                  widget.onSettings,
                ),
              if (widget.onLoop != null)
                _button(
                  Symbols.refresh_rounded,
                  t('media.chartPlayer.loop', 'Loop'),
                  widget.onLoop,
                  selected: widget.loop,
                ),
              _button(
                fullscreen
                    ? Symbols.fullscreen_exit_rounded
                    : Symbols.fullscreen_rounded,
                t(
                  fullscreen
                      ? 'common.actions.fullscreenExit'
                      : 'common.actions.fullscreen',
                  'Fullscreen',
                ),
                () => unawaited(_fullscreen()),
                selected: fullscreen,
              ),
              _button(
                Symbols.expand_more_rounded,
                t('common.actions.collapse', 'Collapse'),
                () {
                  _collapsed = true;
                  widget.onCollapsed?.call(true);
                  _changed();
                },
              ),
            ];
            return AbsorbPointer(
              absorbing: widget.busy,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _button(
                        widget.leadReplay
                            ? Symbols.replay_rounded
                            : (widget.leadActive ?? widget.playing)
                            ? Symbols.pause_rounded
                            : Symbols.play_arrow_rounded,
                        widget.leadLabel ??
                            t(
                              widget.playing
                                  ? 'common.actions.pause'
                                  : 'common.actions.play',
                              'Play',
                            ),
                        widget.onToggle,
                        selected: widget.leadActive,
                      ),
                      Text(
                        widget.positionLabel ?? _clock(value),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Expanded(
                        child: Slider(
                          value: value,
                          max: widget.maximum > 0 ? widget.maximum : 1,
                          semanticFormatterCallback: (v) =>
                              widget.positionLabel == null
                              ? _clock(v)
                              : '${v.round()}',
                          onChangeStart: widget.onSeek == null
                              ? null
                              : (v) {
                                  _hide?.cancel();
                                  _scrub = v;
                                  widget.onScrubStart?.call();
                                  _changed();
                                },
                          onChanged: widget.onSeek == null
                              ? null
                              : (v) {
                                  _scrub = v;
                                  widget.onPreviewSeek?.call(v);
                                  _changed();
                                },
                          onChangeEnd: widget.onSeek == null
                              ? null
                              : (v) {
                                  _scrub = null;
                                  widget.onSeek?.call(v);
                                  _showControls();
                                },
                        ),
                      ),
                      Text(
                        widget.maximumLabel ?? _clock(widget.maximum),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      if (!compact) ...extras,
                    ],
                  ),
                  if (compact)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: extras,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _presentation(BuildContext context, {required bool fullscreen}) {
    final epoch = _presentationEpoch;
    final stage = PlaybackStageScope(
      fullscreen: fullscreen,
      epoch: epoch,
      isCurrent: () =>
          _uiAlive &&
          epoch == _presentationEpoch &&
          fullscreen == (_overlay != null),
      toggleFullscreen: () => unawaited(_fullscreen()),
      setControlsExpanded: (expanded) {
        _collapsed = !expanded;
        widget.onCollapsed?.call(!expanded);
        _showControls();
      },
      child: Builder(
        builder: (context) => FocusableActionDetector(
          autofocus: true,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (widget.onStageActivate != null) {
                  widget.onStageActivate!();
                } else if (widget.playing && widget.onPause != null) {
                  widget.onPause!();
                  _collapsed = false;
                  widget.onCollapsed?.call(false);
                  _showControls();
                } else {
                  widget.onToggle?.call();
                }
                return null;
              },
            ),
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                if (_overlay != null) unawaited(_exitFullscreen());
                return null;
              },
            ),
          },
          child: widget.stage(context),
        ),
      ),
    );
    final presentation = fullscreen
        ? Stack(
            children: [
              Positioned.fill(child: stage),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Visibility(
                  visible: widget.controlsVisible,
                  maintainSize: true,
                  maintainState: true,
                  maintainAnimation: true,
                  child: _controls(context, true),
                ),
              ),
            ],
          )
        : Column(
            children: [
              Expanded(child: stage),
              Visibility(
                visible: widget.controlsVisible,
                maintainSize: true,
                maintainState: true,
                maintainAnimation: true,
                child: _controls(context, false),
              ),
            ],
          );
    return presentation;
  }

  @override
  Widget build(BuildContext context) => _overlay == null
      ? _presentation(context, fullscreen: false)
      : const SizedBox.expand();
}
