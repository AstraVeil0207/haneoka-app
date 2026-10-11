import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_image.dart';
import 'theme.dart';

enum MarkAt { start, end, bottomStart, bottomEnd }

/// An overlay on a tile's artwork: a game emblem, or a short text such as a
/// level or category, pinned 8 dp from a corner (`.tile__mark`).
class TileMark {
  const TileMark.image(this.at, this.image, {this.label})
    : text = null,
      accent = null;
  const TileMark.text(this.at, this.text, {this.accent, this.label})
    : image = null;
  final MarkAt at;
  final String? image;
  final String? text;

  /// Paints the mark in this colour instead of the translucent surface.
  final Color? accent;
  final String? label;
}

/// The collection tile (`src/lit/ui/tile.ts`): a Material card whose media is
/// full bleed, then a two-line headline and a one-line subhead. Marks sit on
/// the artwork; nothing adds a third line.
class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.title,
    required this.images,
    this.titleLanguage,
    this.subtitle,
    this.adornments = const [],
    this.aspectRatio = 1,
    this.fit = BoxFit.contain,
    this.marks = const [],
    this.placeholder,
    this.onTap,
    this.action,
    this.selected = false,
  });
  final String title;

  /// For a tile that chooses something (a challenge song, a band): the
  /// secondary container, as `.tile.is-selected`.
  final bool selected;
  final Locale? titleLanguage;

  /// Null drops the subhead; an empty string keeps its height.
  final String? subtitle;

  /// 16 dp emblems before the subhead (band logo, attribute).
  final List<String> adornments;
  final List<String> images;
  final double aspectRatio;
  final BoxFit fit;
  final List<TileMark> marks;
  final IconData? placeholder;
  final VoidCallback? onTap;

  /// A real action beside the tile's own link, pinned to the artwork's top end.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < ShellMetrics.compact;
    final card = Material(
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corner.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: scheme.onSurface.withValues(alpha: 0.08),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AppImage(
                      candidates: images,
                      fit: fit,
                      placeholder: Center(
                        child: Icon(
                          placeholder ?? Symbols.image_rounded,
                          size: 32,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    for (final mark in marks) _Mark(mark: mark),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 8 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: compact ? 40 : 48,
                    child: Text(
                      title,
                      locale: titleLanguage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: compact
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: compact ? 4 : 8),
                    SizedBox(
                      height: compact ? 18 : 20,
                      child: Row(
                        children: [
                          for (final emblem in adornments) ...[
                            ClipOval(
                              child: SizedBox.square(
                                dimension: 16,
                                child: AppImage(candidates: [emblem]),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              subtitle!,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (compact
                                          ? theme.textTheme.bodySmall?.copyWith(
                                              height: 18 / 12,
                                            )
                                          : theme.textTheme.bodyMedium)
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (action == null) return card;
    return Stack(
      children: [
        card,
        Positioned(top: 8, right: 8, child: action!),
      ],
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.mark});
  final TileMark mark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget child;
    if (mark.image != null) {
      child = SizedBox.square(
        dimension: 24,
        child: AppImage(candidates: [mark.image!]),
      );
    } else {
      final text = Text(
        mark.text!,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: mark.accent == null ? scheme.onSurface : scheme.onPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      final box = Container(
        constraints: const BoxConstraints(minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        alignment: Alignment.center,
        color: mark.accent ?? scheme.surface.withValues(alpha: 0.78),
        child: text,
      );
      child = ClipRRect(
        borderRadius: BorderRadius.circular(Corner.extraSmall),
        child: mark.accent == null
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: box,
              )
            : box,
      );
    }
    final semantic = mark.label == null
        ? child
        : Semantics(label: mark.label, child: child);
    return switch (mark.at) {
      MarkAt.start => Positioned(top: 8, left: 8, child: semantic),
      MarkAt.end => Positioned(top: 8, right: 8, child: semantic),
      MarkAt.bottomStart => Positioned(bottom: 8, left: 8, child: semantic),
      MarkAt.bottomEnd => Positioned(bottom: 8, right: 8, child: semantic),
    };
  }
}

/// The website's page padding: `16px var(--pane-gutter) 32px`, with the
/// gutter `clamp(12px, 2.2vw, 24px)`.
EdgeInsets pagePadding(BuildContext context) {
  final gutter = (MediaQuery.sizeOf(context).width * 0.022).clamp(12.0, 24.0);
  return EdgeInsets.fromLTRB(gutter, 16, gutter, 32);
}

/// The website's collection grid (`.collection`): tiles at least [minWidth]
/// wide; three columns below 840 dp; two on compact windows, three there for
/// small symbols from 390 dp. Rows are as tall as the tile's media plus its
/// fixed text block, so every tile in the grid shares one baseline.
SliverGridDelegate collectionGrid(
  BuildContext context,
  double width, {
  required double minWidth,
  double aspectRatio = 1,
  bool subtitle = true,
  bool small = false,
}) {
  final viewport = MediaQuery.sizeOf(context).width;
  final compact = viewport < ShellMetrics.compact;
  final gap = compact ? 8.0 : 12.0;
  int columns;
  if (compact) {
    columns = small && viewport >= 390 ? 3 : 2;
  } else if (viewport < 840) {
    columns = 3;
  } else {
    columns = ((width + gap) / (minWidth + gap)).floor().clamp(1, 99);
  }
  final tile = (width - gap * (columns - 1)) / columns;
  final text = compact
      ? 16 + 40 + (subtitle ? 4 + 18 : 0)
      : 32 + 48 + (subtitle ? 8 + 20 : 0);
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: gap,
    crossAxisSpacing: gap,
    mainAxisExtent: tile / aspectRatio + text,
  );
}
