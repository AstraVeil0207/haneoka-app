import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'adv_text.dart';
import 'app_image.dart';
import 'theme.dart';

/// Shared transcript and character-voice row, matching the web dialogue row.
class DialogueRow extends StatelessWidget {
  const DialogueRow({
    super.key,
    required this.name,
    required this.content,
    this.faces = const [],
    this.action,
    this.playing = false,
  });

  static const spacing = 16.0;
  final String name;
  final List<String> faces;
  final Widget content;
  final Widget? action;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < ShellMetrics.compact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (name.isNotEmpty || faces.isNotEmpty) ...[
          Row(
            children: [
              Wrap(
                spacing: 4,
                children: [
                  if (faces.isEmpty)
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: scheme.surfaceContainerHigh,
                      child: Icon(
                        Symbols.person_rounded,
                        size: 24,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  for (final face in faces)
                    ClipOval(
                      child: SizedBox.square(
                        dimension: 32,
                        child: ColoredBox(
                          color: scheme.surfaceContainerHigh,
                          child: AppImage(candidates: [face]),
                        ),
                      ),
                    ),
                ],
              ),
              if (name.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: AdvText(name, style: theme.textTheme.titleSmall),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
        Container(
          padding: EdgeInsets.symmetric(
            vertical: compact ? 8 : 12,
            horizontal: compact ? 12 : 16,
          ),
          decoration: BoxDecoration(
            color: playing
                ? scheme.primaryContainer
                : scheme.surfaceContainerLow,
            border: Border.all(
              color: playing ? scheme.primary : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(Corner.medium),
          ),
          child: Row(
            children: [
              Expanded(
                child: DefaultTextStyle.merge(
                  style:
                      (compact
                              ? theme.textTheme.bodyMedium
                              : theme.textTheme.bodyLarge)
                          ?.copyWith(
                            color: playing
                                ? scheme.onPrimaryContainer
                                : scheme.onSurface,
                          ),
                  child: content,
                ),
              ),
              if (action != null) ...[
                SizedBox(width: compact ? 8 : 12),
                action!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
