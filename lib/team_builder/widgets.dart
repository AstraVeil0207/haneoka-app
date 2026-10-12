/// Building blocks the team builder's tabs share: tool sections, headings,
/// segmented choices, card art and song rows.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_new_shapes/material_new_shapes.dart';

import '../ui/app_image.dart';
import '../ui/shapes.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';
import 'catalog.dart';
import 'engine/api.dart';

/// A tool settings section (`.surface` with `detail-section-title`).
class ToolSection extends StatelessWidget {
  const ToolSection({
    super.key,
    this.icon,
    this.title,
    this.count,
    this.trailing,
    required this.children,
  });
  final IconData? icon;
  final String? title;
  final String? count;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Corner.extraLarge),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: trailing == null
                    ? SectionHeading(icon: icon, title: title!, count: count)
                    : Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          SectionHeading(
                            icon: icon,
                            title: title!,
                            count: count,
                          ),
                          trailing!,
                        ],
                      ),
              ),
            ...[
              for (final (index, child) in children.indexed) ...[
                if (index > 0) const SizedBox(height: 12),
                child,
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    this.icon,
    required this.title,
    this.count,
    this.trailing,
  });
  final IconData? icon;
  final String title;
  final String? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: trailing == null ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (icon != null) ...[
          ShapedIcon(
            shape: MaterialShapes.cookie9Sided,
            size: 40,
            child: Icon(icon, size: 22),
          ),
          const SizedBox(width: 12),
        ],
        Flexible(child: Text(title, style: theme.textTheme.titleLarge)),
        if (count != null) ...[
          const SizedBox(width: 8),
          Text(
            count!,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

/// A labelled field: label above, control below (`.tb-field`).
class ToolField extends StatelessWidget {
  const ToolField({
    super.key,
    required this.label,
    this.value,
    required this.child,
  });
  final String label;
  final String? value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (value != null) Text(value!, style: theme.textTheme.labelLarge),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class Choice<T> {
  const Choice(this.value, this.label, [this.icon]);
  final T value;
  final String label;
  final IconData? icon;
}

/// A single-choice segmented control that wraps rather than overflowing.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.grow = true,
  });
  final T value;
  final List<Choice<T>> options;
  final ValueChanged<T> onSelected;
  final bool grow;

  @override
  Widget build(BuildContext context) {
    // Many options (difficulties, ranks) wrap as chips; few fill the width.
    if (options.length > 4 || !grow) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            ChoiceChip(
              avatar: option.icon == null ? null : Icon(option.icon, size: 18),
              showCheckmark: false,
              label: Text(option.label),
              selected: option.value == value,
              onSelected: (_) => onSelected(option.value),
            ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [
          for (final option in options)
            ButtonSegment(
              value: option.value,
              icon: option.icon == null ? null : Icon(option.icon, size: 18),
              label: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        selected: {value},
        onSelectionChanged: (selected) => onSelected(selected.single),
      ),
    );
  }
}

/// A card's art at its frame ratio, with the catalogue's emblems.
class CardArt extends StatelessWidget {
  const CardArt({
    super.key,
    required this.catalog,
    required this.members,
    required this.id,
    this.extra = const [],
    this.emblems = true,
  });
  final TeamCatalog catalog;
  final bool members;
  final int id;
  final List<TileMark> extra;
  final bool emblems;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: members ? 3 / 4 : 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Corner.small),
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppImage(
                candidates: [catalog.cardImage(members, id)],
                fit: BoxFit.cover,
              ),
              if (emblems)
                for (final mark in catalog.cardMarks(members, id))
                  _SmallMark(mark),
              for (final mark in extra) _SmallMark(mark),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallMark extends StatelessWidget {
  const _SmallMark(this.mark);
  final TileMark mark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget child = mark.image != null
        ? SizedBox.square(
            dimension: 16,
            child: AppImage(candidates: [mark.image!]),
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: (mark.accent ?? Colors.black).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              child: Text(
                mark.text ?? '',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontSize: 10,
                ),
              ),
            ),
          );
    final semantic = mark.label == null
        ? child
        : Tooltip(message: mark.label!, child: child);
    return switch (mark.at) {
      MarkAt.start => Positioned(left: 4, top: 4, child: semantic),
      MarkAt.end => Positioned(right: 4, top: 4, child: semantic),
      MarkAt.bottomStart => Positioned(left: 4, bottom: 4, child: semantic),
      MarkAt.bottomEnd => Positioned(right: 4, bottom: 4, child: semantic),
    };
  }
}

/// A chosen song: jacket, title and difficulty.
class SongRow extends StatelessWidget {
  const SongRow({
    super.key,
    required this.catalog,
    required this.song,
    this.trailing,
    this.onTap,
  });
  final TeamCatalog catalog;
  final SongRef song;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: onTap,
    leading: ClipRRect(
      borderRadius: BorderRadius.circular(Corner.small),
      child: SizedBox.square(
        dimension: 48,
        child: AppImage(
          candidates: [catalog.songJacket(song.songId)],
          fit: BoxFit.cover,
        ),
      ),
    ),
    title: Text(
      catalog.songTitle(song.songId),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(catalog.difficultyLabel(song.songId, song.difficulty)),
    trailing: trailing,
  );
}

/// A labelled value chip (`.tb-chip`).
class ValueChip extends StatelessWidget {
  const ValueChip({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });
  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Corner.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: theme.textTheme.labelLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String formatNumber(String locale, num value, [int digits = 0]) =>
    (NumberFormat.decimalPattern(locale)
          ..minimumFractionDigits = digits
          ..maximumFractionDigits = digits)
        .format(value);

/// Pill tabs in a tonal bar (`.tabs--pills`), scrolling sideways when narrow.
class PillTabs<T> extends StatelessWidget {
  const PillTabs({
    super.key,
    required this.value,
    required this.tabs,
    required this.onSelected,
  });
  final T value;
  final List<(T, IconData, String, int?)> tabs;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Corner.large),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final (tab, icon, label, count) in tabs)
              Material(
                color: tab == value
                    ? scheme.secondaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(40),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelected(tab),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 18,
                          color: tab == value
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: tab == value
                                ? scheme.onSecondaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        if (count != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '$count',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
