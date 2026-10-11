import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'app_image.dart';
import 'theme.dart';

/// The website's detail layout (`detailLayout`): media beside the sections on
/// wide windows, above them on narrow ones.
class DetailLayout extends StatelessWidget {
  const DetailLayout({super.key, this.media, required this.sections});
  final Widget? media;
  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      (MediaQuery.sizeOf(context).width * 0.022).clamp(12.0, 24.0),
      16,
      (MediaQuery.sizeOf(context).width * 0.022).clamp(12.0, 24.0),
      32,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: sections,
        );
        if (constraints.maxWidth >= 840 && media != null) {
          return SingleChildScrollView(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: (constraints.maxWidth * 0.36).clamp(280, 440),
                  child: media,
                ),
                const SizedBox(width: 24),
                Expanded(child: column),
              ],
            ),
          );
        }
        return ListView(
          padding: padding,
          children: [
            if (media != null) ...[media!, const SizedBox(height: 16)],
            column,
          ],
        );
      },
    );
  }
}

/// A detail section (`renderDetailSectionHeading`): an icon in a tonal
/// circle, the title and a count, over its content; long groups fold.
class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.count,
    this.folded = false,
  });
  final IconData icon;
  final String title;
  final int? count;
  final Widget child;
  final bool folded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final heading = Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: scheme.secondaryContainer,
          child: Icon(icon, size: 20, color: scheme.onSecondaryContainer),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            title,
            style: theme.textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Corner.full),
            ),
            child: Text('$count', style: theme.textTheme.labelSmall),
          ),
        ],
      ],
    );
    if (folded) {
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        title: heading,
        children: [child],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [heading, const SizedBox(height: 16), child],
      ),
    );
  }
}

/// One fact: a label above its value, which may be a widget (an emblem).
class Fact {
  const Fact(this.label, this.value, {this.widget});
  final String label;
  final String value;
  final Widget? widget;
}

/// Facts as the website's `.spec-list`: label above value, two columns.
class SpecList extends StatelessWidget {
  const SpecList({super.key, required this.facts});
  final List<Fact> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 280 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final fact in facts)
              SizedBox(
                width: fact.value.length > 40 ? constraints.maxWidth : width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fact.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    fact.widget ??
                        SelectableText(
                          fact.value,
                          style: theme.textTheme.titleMedium,
                        ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The website's difficulty colours (`--md-extended-color-difficulty-*`).
const difficultyColors = [
  Color(0xFF48CADC),
  Color(0xFF56CE79),
  Color(0xFFF4BB3C),
  Color(0xFFE84E43),
  Color(0xFFC950D7),
];

/// The static difficulty picker: one tinted chip per chart with its level.
class DifficultyChips extends StatelessWidget {
  const DifficultyChips({
    super.key,
    required this.levels,
    this.selected,
    this.onSelected,
  });

  /// (difficulty index, name, level).
  final List<(int, String, String)> levels;
  final int? selected;
  final ValueChanged<int>? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (index, name, level) in levels)
          Builder(
            builder: (context) {
              final color = difficultyColors[index.clamp(0, 4)];
              final checked = selected == index;
              return Material(
                color: checked
                    ? color
                    : Color.alphaBlend(
                        color.withValues(alpha: 0.18),
                        scheme.surface,
                      ),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: Color.lerp(color, scheme.outline, 0.3)!,
                  ),
                  borderRadius: BorderRadius.circular(
                    checked ? Corner.medium : Corner.large,
                  ),
                ),
                child: InkWell(
                  onTap: onSelected == null ? null : () => onSelected!(index),
                  customBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Corner.large),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 56,
                      minHeight: 52,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: checked ? const Color(0xFF121318) : null,
                            ),
                          ),
                          Text(
                            level,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: checked ? const Color(0xFF121318) : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// The detail's artwork (`image-gallery`): an outlined card, one image at a
/// time with a zoom button, a pager and a strip of thumbnails.
class ImageGallery extends StatefulWidget {
  const ImageGallery({super.key, required this.images, this.aspectRatio = 1});
  final List<String> images;
  final double aspectRatio;
  @override
  State<ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<ImageGallery> {
  int _index = 0;
  final _pages = PageController();

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index) => _pages.animateToPage(
    index,
    duration: Durations.medium2,
    curve: Easing.standard,
  );

  void _zoom(BuildContext context) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (context, _, _) =>
          _ZoomView(images: widget.images, initial: _index),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final images = widget.images;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(Corner.extraLarge),
      ),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: widget.aspectRatio,
            child: Stack(
              children: [
                PageView(
                  controller: _pages,
                  onPageChanged: (index) => setState(() => _index = index),
                  children: [
                    for (final image in images)
                      GestureDetector(
                        onTap: () => _zoom(context),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: AppImage(candidates: [image]),
                        ),
                      ),
                  ],
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: IconButton.filledTonal(
                    tooltip: MaterialLocalizations.of(context).expandedHint,
                    onPressed: () => _zoom(context),
                    icon: const Icon(Symbols.zoom_in_rounded),
                  ),
                ),
              ],
            ),
          ),
          if (images.length > 1) ...[
            Divider(height: 1, color: scheme.outlineVariant),
            Row(
              children: [
                IconButton(
                  onPressed: _index == 0 ? null : () => _go(_index - 1),
                  icon: const Icon(Symbols.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_index + 1} / ${images.length}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                IconButton(
                  onPressed: _index == images.length - 1
                      ? null
                      : () => _go(_index + 1),
                  icon: const Icon(Symbols.chevron_right_rounded),
                ),
              ],
            ),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => InkWell(
                  onTap: () => _go(index),
                  borderRadius: BorderRadius.circular(Corner.small),
                  child: Container(
                    width: 52,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(Corner.small),
                      border: Border.all(
                        width: 2,
                        color: index == _index
                            ? scheme.primary
                            : Colors.transparent,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: AppImage(candidates: [images[index]]),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen pinch zoom over the gallery (`photo_view`).
class _ZoomView extends StatelessWidget {
  const _ZoomView({required this.images, required this.initial});
  final List<String> images;
  final int initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            itemCount: images.length,
            pageController: PageController(initialPage: initial),
            builder: (context, index) => PhotoViewGalleryPageOptions(
              imageProvider: CachedNetworkImageProvider(images[index]),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
            ),
          ),
          SafeArea(
            child: IconButton(
              color: Colors.white,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Symbols.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
