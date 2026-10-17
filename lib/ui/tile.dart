import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_image.dart';
import 'theme.dart';

enum MarkAt { start, end, bottomStart, bottomEnd }

/// An overlay on a tile's artwork: a game emblem, or a short text such as a
/// level or category, pinned 8 dp from a corner (`.tile__mark`).
class TileMark {
  const TileMark.image(this.at, this.image, {this.label})
    : text = null,
      accent = null,
      alert = false;
  const TileMark.text(
    this.at,
    this.text, {
    this.accent,
    this.label,
    this.alert = false,
  }) : image = null;

  /// The error colour (`accent: var(--md-sys-color-error)`): ended, retired.
  final bool alert;
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
    this.adornmentPortraitStart = 0,
    this.aspectRatio = 1,
    this.fit = BoxFit.contain,
    this.marks = const [],
    this.placeholder,
    this.onTap,
    this.action,
    this.selected = false,
    this.media,
    this.accent,
    this.alignment = Alignment.center,
    this.serverMark,
    this.rail = false,
  });

  /// The one server an entity is on: its publisher's emblem and its label
  /// (`.tile__server-mark`).
  final (String asset, String label)? serverMark;

  /// The subject's colour, tinting the media box (`--entity-accent` on
  /// character and band tiles).
  final Color? accent;

  /// Where the artwork sits in its box: characters are framed head-first.
  final Alignment alignment;
  final bool rail;
  final String title;

  /// Drawn instead of [images]: a composed figure such as two faces.
  final Widget? media;

  /// For a tile that chooses something (a challenge song, a band): the
  /// secondary container, as `.tile.is-selected`.
  final bool selected;
  final Locale? titleLanguage;

  /// Null drops the subhead; an empty string keeps its height.
  final String? subtitle;

  /// 16 dp emblems before the subhead (band logo, attribute).
  final List<String> adornments;
  final int adornmentPortraitStart;
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
    final dense = compact && !rail;
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  gradient: accent == null
                      ? null
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color.alphaBlend(
                              accent!.withValues(alpha: 0.26),
                              scheme.surfaceContainerHighest,
                            ),
                            scheme.surfaceContainerHighest,
                          ],
                        ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ?media,
                    if (media == null)
                      AppImage(
                        candidates: images,
                        fit: fit,
                        alignment: alignment,
                        placeholder: Center(
                          child: Icon(
                            placeholder ?? Symbols.image_rounded,
                            size: 32,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    for (final mark in marks)
                      _Mark(mark: mark, beside: serverMark != null),
                    if (serverMark case (final asset, final label))
                      Positioned(
                        right: 8,
                        bottom: 8,
                        width: 18,
                        height: 18,
                        child: Tooltip(
                          message: label,
                          child: SvgPicture.asset(asset, semanticsLabel: label),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(
                dense
                    ? 8
                    : compact
                    ? 12
                    : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: dense ? 40 : 48,
                    child: Text(
                      title,
                      locale: titleLanguage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: dense
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.titleMedium,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: compact ? 4 : 8),
                    SizedBox(
                      height: dense ? 18 : 20,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final crowded =
                              adornments.length - adornmentPortraitStart >= 4 &&
                              constraints.maxWidth < 144;
                          return Row(
                            children: [
                              // Several faces overlap as a stack
                              // (`catalogPortraitStack`).
                              for (final (index, emblem)
                                  in adornments.take(5).indexed)
                                Align(
                                  widthFactor:
                                      index >= adornmentPortraitStart &&
                                          index + 1 < adornments.take(5).length
                                      ? (crowded ? 0.6 : 0.7)
                                      : 1,
                                  child: index < adornmentPortraitStart
                                      ? SizedBox.square(
                                          dimension: 16,
                                          child: AppImage(candidates: [emblem]),
                                        )
                                      : ClipOval(
                                          child: SizedBox.square(
                                            dimension: 16,
                                            child: AppImage(
                                              candidates: [emblem],
                                            ),
                                          ),
                                        ),
                                ),
                              if (adornments.isNotEmpty)
                                SizedBox(width: crowded ? 4 : 8),
                              Expanded(
                                child: Text(
                                  subtitle!,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      ((dense || crowded)
                                              ? theme.textTheme.bodySmall
                                              : theme.textTheme.bodyMedium)
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                ),
                              ),
                            ],
                          );
                        },
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
  const _Mark({required this.mark, this.beside = false});
  final TileMark mark;

  /// Leaves room for the server emblem in the bottom-end corner.
  final bool beside;

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
          color: mark.accent == null && !mark.alert
              ? scheme.onSurface
              : scheme.onPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
      final box = Container(
        constraints: const BoxConstraints(minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        alignment: Alignment.center,
        color:
            mark.accent ??
            (mark.alert
                ? scheme.error
                : scheme.surface.withValues(alpha: 0.78)),
        child: text,
      );
      child = ClipRRect(
        borderRadius: BorderRadius.circular(Corner.extraSmall),
        child: mark.accent == null && !mark.alert
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
      MarkAt.bottomEnd => Positioned(
        bottom: 8,
        right: beside ? 34 : 8,
        child: semantic,
      ),
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
    final preferred = (minWidth * 0.9).clamp(0.0, 200.0);
    columns = ((width + gap) / (preferred + gap)).floor().clamp(1, 99);
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

/// An event's tile artwork (`eventArtwork`): its top image cropped from the
/// left, the event logo over the right.
class EventArtwork extends StatelessWidget {
  const EventArtwork({
    super.key,
    required this.background,
    required this.logo,
    this.logoWidth = 0.42,
  });
  final String background;
  final String logo;
  final double logoWidth;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      AppImage(
        candidates: [background],
        fit: BoxFit.cover,
        alignment: const Alignment(-0.4, -0.3),
      ),
      FractionallySizedBox(
        alignment: const Alignment(0.92, 0),
        widthFactor: logoWidth,
        child: AppImage(candidates: [logo]),
      ),
    ],
  );
}
