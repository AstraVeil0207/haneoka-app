import 'dart:async';

import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/render_preferences.dart';

/// Shared immediate-apply controls for story and chart player hosts.
final class RenderQualitySettings extends StatelessWidget {
  const RenderQualitySettings({
    super.key,
    required this.preferences,
    required this.text,
  });
  final RenderPreferences preferences;
  final SiteText text;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: preferences,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(text('media.rendering.title', 'Graphics')),
          subtitle: Text(text('media.rendering.description', 'FSR 1')),
        ),
        ListTile(
          title: Text(text('media.rendering.resolution', 'Scene resolution')),
          trailing: DropdownButton<double>(
            value: preferences.factor,
            items: [
              DropdownMenuItem(
                value: 1,
                child: Text(text('media.rendering.native', 'Native')),
              ),
              DropdownMenuItem(
                value: 1.3,
                child: Text(
                  '${text('media.rendering.quality', 'Quality')} (1.3×)',
                ),
              ),
              DropdownMenuItem(
                value: 1.5,
                child: Text(
                  '${text('media.rendering.balanced', 'Balanced')} (1.5×)',
                ),
              ),
            ],
            onChanged: (value) {
              if (value != null) unawaited(preferences.setFactor(value));
            },
          ),
        ),
        ListTile(
          title: Text(text('media.rendering.sharpness', 'Sharpness')),
          trailing: Text('${(preferences.sharpness * 100).round()}%'),
          subtitle: Slider(
            value: preferences.sharpness,
            min: 0,
            max: 1,
            divisions: 100,
            onChanged: preferences.factor > 1
                ? (value) => unawaited(preferences.setSharpness(value))
                : null,
          ),
        ),
      ],
    ),
  );
}
