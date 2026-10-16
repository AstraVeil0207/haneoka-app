import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart'
    show haneokaProfileAssetRoot;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';

/// A host supplies actions; the shared game theme supplies order and labels.
class StoryPlayerMenu extends StatelessWidget {
  const StoryPlayerMenu({
    super.key,
    required this.controls,
    required this.locale,
    required this.height,
    required this.actions,
    this.selected = const {},
    this.enabled = const {},
    this.busy = false,
    this.menuKey,
  });
  final StoryPlayerControls controls;
  final String locale;
  final double height;
  final Map<String, VoidCallback> actions;
  final Map<String, bool> selected;
  final Map<String, bool> enabled;
  final bool busy;
  final GlobalKey<PopupMenuButtonState<String>>? menuKey;
  static const _assets = '${haneokaProfileAssetRoot}story-controls/';
  static const _icons = {
    'auto',
    'fast',
    'skip',
    'log',
    'fullscreen',
    'continuous',
  };

  @override
  Widget build(BuildContext context) {
    final labels = controls.forLocale(locale);
    final face = height * 120 / 1080;
    final target = math.max(44.0, face);
    return Positioned(
      top: height * 8 / 1080,
      right: height * 84 / 1080,
      width: target,
      height: target,
      child: PopupMenuButton<String>(
        enabled: !busy,
        key: menuKey,
        tooltip: labels['menu'],
        color: const Color(0xed101a34),
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
        onSelected: (id) => actions[id]?.call(),
        itemBuilder: (_) {
          final entries = <PopupMenuEntry<String>>[];
          for (final group in controls.groups) {
            final available = group.actions.where(actions.containsKey).toList();
            if (available.isEmpty) continue;
            if (entries.isNotEmpty) entries.add(const PopupMenuDivider());
            for (final id in available) {
              entries.add(
                PopupMenuItem<String>(
                  value: id,
                  enabled: enabled[id] ?? true,
                  height: 44,
                  child: Row(
                    children: [
                      if (_icons.contains(id)) ...[
                        Image.asset('$_assets$id.png', width: 24, height: 24),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          labels[id]!,
                          style: const TextStyle(color: Color(0xffedf3ff)),
                        ),
                      ),
                      if (selected[id] == true)
                        const Icon(
                          Icons.check,
                          size: 18,
                          color: Color(0xffb5eee3),
                        ),
                    ],
                  ),
                ),
              );
            }
          }
          return entries;
        },
        child: Align(
          alignment: Alignment.topRight,
          child: SizedBox(
            width: face,
            height: face,
            child: Stack(
              children: [
                Image.asset('${_assets}menuFrame.png', fit: BoxFit.fill),
                Positioned.fill(
                  child: FractionallySizedBox(
                    widthFactor: .5,
                    heightFactor: .5,
                    child: Image.asset(
                      '${_assets}menuOpen.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
