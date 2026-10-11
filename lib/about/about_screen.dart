import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_state.dart';
import '../shell/links.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/shapes.dart';
import '../ui/tile.dart';

const _origin = 'https://haneoka.org';
const _cast = [
  ('tomori_takamatsu', 'cookie12'),
  ('uika_misumi', 'arch'),
  ('arale_nakamachi', 'pill'),
  ('hotaru_shiomi', 'flower'),
  ('raika_suga', 'slanted'),
];
const _features = [
  (Symbols.auto_stories_rounded, 'cookie9', 'tomori_takamatsu', '/catalog'),
  (Symbols.music_note_rounded, 'sunny', 'uika_misumi', '/catalog/songs'),
  (Symbols.groups_rounded, 'clover4', 'arale_nakamachi', '/team-builder'),
  (
    Symbols.theater_comedy_rounded,
    'flower',
    'hotaru_shiomi',
    '/catalog/stories/event',
  ),
  (
    Symbols.monitoring_rounded,
    'softBurst',
    'raika_suga',
    '/catalog/events/tracker',
  ),
  (Symbols.forum_rounded, 'cookie6', 'tomori_takamatsu', '/community'),
];
RoundedPolygon _shape(String name) => switch (name) {
  'cookie12' => MaterialShapes.cookie12Sided,
  'cookie9' => MaterialShapes.cookie9Sided,
  'cookie6' => MaterialShapes.cookie6Sided,
  'arch' => MaterialShapes.arch,
  'pill' => MaterialShapes.pill,
  'flower' => MaterialShapes.flower,
  'slanted' => MaterialShapes.slanted,
  'sunny' => MaterialShapes.sunny,
  'clover4' => MaterialShapes.clover4Leaf,
  _ => MaterialShapes.softBurst,
};
String _repo(String name) => 'https://github.com/haneoka-gakuen/$name';

/// About Haneoka (`AboutPage`): what the site and app are, the live counts,
/// each part with where it lives, the open projects behind them and the
/// links that matter, plus this app's version.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  Future<Object?>? _summary;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _summary ??= AppScope.of(context).api
        .catalog('catalog/summary')
        .then<Object?>((v) => v, onError: (_) => null);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String about(String key, [String fallback = '']) =>
        t('legal.about.$key', fallback);
    final navigate = ShellScope.of(context)?.navigate;
    final view = MediaQuery.sizeOf(context).width;
    final wide = view >= 840;
    final compact = view < 600;
    double clamp(double min, double vw, double max) =>
        (view * vw / 100).clamp(min, max);
    final display = theme.textTheme.displayLarge?.copyWith(
      fontSize: clamp(40, 5.4, 64),
      fontWeight: FontWeight.w500,
      height: 1.1,
      letterSpacing: -0.02 * clamp(40, 5.4, 64),
    );
    final headline = theme.textTheme.headlineMedium?.copyWith(
      fontSize: clamp(28, 3.2, 40),
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    final lede = theme.textTheme.bodyLarge?.copyWith(
      fontSize: clamp(17, 1.6, 20),
      height: 1.5,
      color: scheme.onSurfaceVariant,
    );
    final body = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.6,
    );
    final gap = clamp(64, 9, 128);
    Widget eyebrow(String text) => Text(
      text,
      style: theme.textTheme.labelLarge?.copyWith(
        color: scheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
    Widget cta() => SizedBox(
      height: 56,
      width: compact ? double.infinity : null,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: theme.textTheme.titleMedium,
        ),
        onPressed: () => navigate?.call('/catalog'),
        icon: const Icon(Symbols.arrow_forward_rounded),
        iconAlignment: IconAlignment.end,
        label: Text(about('ctaPrimary')),
      ),
    );
    Widget shaped(
      String slug,
      String shape,
      Color ground, {
      double ratio = 1,
    }) => ClipPath(
      clipper: PolygonClipper(_shape(shape)),
      child: ColoredBox(
        color: ground,
        child: AspectRatio(
          aspectRatio: ratio,
          child: AppImage(
            candidates: ['$_origin/images/about/$slug.webp'],
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.84),
            localized: false,
          ),
        ),
      ),
    );

    // The cast, placed as `.about-cast__member--n` (left, top, width in %).
    const placements = [
      (0.28, 0.06, 0.46),
      (0.0, 0.36, 0.32),
      (0.72, 0.0, 0.28),
      (0.62, 0.50, 0.38),
      (0.22, 0.66, 0.34),
    ];
    final cast = AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth;
          return Stack(
            children: [
              for (final (index, (slug, shape)) in _cast.indexed)
                Positioned(
                  left: side * placements[index].$1,
                  top: side * placements[index].$2,
                  width: side * placements[index].$3,
                  child: shaped(
                    slug,
                    shape,
                    index == 0
                        ? scheme.secondaryContainer
                        : scheme.surfaceContainerHigh,
                  ),
                ),
            ],
          );
        },
      ),
    );
    final heroCopy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        eyebrow(about('eyebrow')),
        const SizedBox(height: 24),
        Text(about('heroTitle'), style: display),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 36 * 18),
          child: Text(about('description'), style: lede),
        ),
        const SizedBox(height: 32),
        cta(),
      ],
    );
    final hero = wide
        ? Row(
            children: [
              Expanded(flex: 105, child: heroCopy),
              SizedBox(width: clamp(32, 5, 72)),
              Expanded(flex: 95, child: cast),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heroCopy,
              SizedBox(height: clamp(32, 5, 72)),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: cast,
                ),
              ),
            ],
          );

    final stats = FutureBuilder(
      future: _summary,
      builder: (context, snapshot) {
        final resources =
            ((snapshot.data as Map?)?['resources'] as Map?) ?? const {};
        num count(List<String> keys) => keys.fold<num>(
          0,
          (sum, key) =>
              sum + (((resources[key] as Map?)?['count'] as num?) ?? 0),
        );
        final number = NumberFormat.decimalPattern(t.locale);
        final values = [
          ('songs', count(['songs'])),
          ('cards', count(['cards', 'support-cards'])),
          ('stories', count(['stories'])),
          ('voices', count(['voices'])),
          ('models', count(['live2d', 'spine'])),
        ].where((e) => e.$2 > 0).toList();
        if (values.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = compact
                  ? 2
                  : ((constraints.maxWidth + 24) / 164).floor().clamp(
                      1,
                      values.length,
                    );
              final width =
                  (constraints.maxWidth - 24 * (columns - 1)) / columns;
              return Wrap(
                spacing: 24,
                runSpacing: 24,
                children: [
                  for (final (key, value) in values)
                    SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            number.format(value),
                            style: theme.textTheme.displayMedium?.copyWith(
                              fontSize: clamp(36, 4, 52),
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            about('stats.$key'),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );

    Widget feature(int index) {
      final (icon, shape, slug, route) = _features[index];
      final media = AspectRatio(
        aspectRatio: 5 / 4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(48),
          child: ColoredBox(
            color: scheme.surfaceContainer,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth, h = constraints.maxHeight;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      left: w * 0.10,
                      top: h * 0.16,
                      width: w * 0.44,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipPath(
                          clipper: PolygonClipper(_shape(shape)),
                          child: ColoredBox(
                            color: scheme.primaryContainer,
                            child: Center(
                              child: Icon(
                                icon,
                                size: clamp(40, 5, 64),
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: w * 0.08,
                      bottom: -h * 0.04,
                      width: w * 0.46,
                      child: shaped(
                        slug,
                        'arch',
                        scheme.surfaceContainerHighest,
                        ratio: 4 / 5,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          eyebrow(about('features.$index.eyebrow')),
          const SizedBox(height: 16),
          Text(about('features.$index.title'), style: headline),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 34 * 16),
            child: Text(about('features.$index.body'), style: body),
          ),
          const SizedBox(height: 8),
          Transform.translate(
            offset: const Offset(-12, 0),
            child: TextButton.icon(
              onPressed: () => navigate?.call(route),
              icon: const Icon(Symbols.arrow_forward_rounded),
              iconAlignment: IconAlignment.end,
              label: Text(about('features.$index.cta')),
            ),
          ),
        ],
      );
      if (!wide) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            media,
            SizedBox(height: clamp(32, 6, 96)),
            copy,
          ],
        );
      }
      final space = SizedBox(width: clamp(32, 6, 96));
      return Row(
        children: index.isOdd
            ? [Expanded(child: copy), space, Expanded(child: media)]
            : [Expanded(child: media), space, Expanded(child: copy)],
      );
    }

    // Two suites share the site: Vega · Altair · Deneb tell stories;
    // Cassiopeia · Schedar play and chart them.
    final suites = [
      (
        'platform',
        [
          (
            Symbols.archive_rounded,
            'repositories.0',
            'ecosystem.0',
            _repo('haneoka'),
          ),
          (Symbols.extension_rounded, 'ecosystem.3', null, _repo('haneoka')),
        ],
      ),
      (
        'story',
        [
          (
            Symbols.auto_stories_rounded,
            'repositories.1',
            'ecosystem.1',
            _repo('vega'),
          ),
          (
            Symbols.edit_rounded,
            'repositories.5',
            'toolchain.1',
            _repo('altair'),
          ),
          (
            Symbols.inventory_2_rounded,
            'repositories.6',
            'toolchain.2',
            _repo('deneb'),
          ),
        ],
      ),
      (
        'rhythm',
        [
          (
            Symbols.music_note_rounded,
            'repositories.2',
            'ecosystem.2',
            _repo('cassiopeia'),
          ),
          (
            Symbols.edit_note_rounded,
            'toolchain.0',
            null,
            '/chart-editor/create',
          ),
          (
            Symbols.sports_esports_rounded,
            'repositories.3',
            null,
            _repo('cassiopeia-plugin-sonolus'),
          ),
          (
            Symbols.sports_esports_rounded,
            'repositories.4',
            null,
            _repo('sonolus-our-notes'),
          ),
        ],
      ),
    ];
    Widget repository(IconData icon, String key, String? detail, String href) {
      final external = href.startsWith('http');
      return Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              external ? openLink(context, href) : navigate?.call(href),
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShapedIcon(
                  shape: MaterialShapes.cookie9Sided,
                  size: 40,
                  child: Icon(icon, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        about('$key.title'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (key.startsWith('repositories')) ...[
                        const SizedBox(height: 4),
                        Text(
                          about('$key.body'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      if (detail != null ||
                          !key.startsWith('repositories')) ...[
                        const SizedBox(height: 4),
                        Text(
                          about('${detail ?? key}.body'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: 16),
                  Icon(
                    external
                        ? Symbols.open_in_new_rounded
                        : Symbols.arrow_forward_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final docs = t.locale == 'zh-CN'
        ? 'https://docs.haneoka.org/zh-cn/'
        : 'https://docs.haneoka.org/';
    final footer = [
      (
        Symbols.sports_esports_rounded,
        'Sonolus',
        'https://open.sonolus.com/haneoka.org',
      ),
      (Symbols.code_rounded, about('apiLink'), docs),
      (null, about('sourceLink'), _repo('haneoka')),
      (null, about('licenseLink'), '${_repo('haneoka')}/blob/main/LICENSE'),
      (
        null,
        about('noticesLink'),
        '${_repo('haneoka')}/blob/main/THIRD_PARTY_NOTICES.md',
      ),
      (null, about('contactLink'), '${_repo('haneoka')}/issues'),
      (null, 'haneoka-app', _repo('haneoka-app')),
    ];

    Widget grid(List<Widget> children) => LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + 12) / 352).floor().clamp(1, 4);
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );

    return ShellPage(
      title: about('title', 'About'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          pagePadding(context).left,
          clamp(24, 5, 64),
          pagePadding(context).right,
          48,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  SizedBox(height: gap),
                  stats,
                  for (var index = 0; index < _features.length; index++) ...[
                    SizedBox(height: gap),
                    feature(index),
                  ],
                  SizedBox(height: gap),
                  Text(about('openTitle'), style: headline),
                  const SizedBox(height: 16),
                  Text(about('openBody'), style: body),
                  for (final (key, items) in suites) ...[
                    const SizedBox(height: 32),
                    Text(
                      about('suites.$key'),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    grid([
                      for (final (icon, title, detail, href) in items)
                        repository(icon, title, detail, href),
                    ]),
                  ],
                  SizedBox(height: gap),
                  Container(
                    padding: EdgeInsets.symmetric(
                      vertical: clamp(48, 8, 96),
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(48),
                    ),
                    child: Column(
                      children: [
                        Text(
                          about('closingTitle'),
                          textAlign: TextAlign.center,
                          style: display?.copyWith(fontSize: clamp(32, 4, 48)),
                        ),
                        const SizedBox(height: 32),
                        cta(),
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 24,
                    runSpacing: 8,
                    children: [
                      for (final (icon, label, href) in footer)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => openLink(context, href),
                          icon: icon == null ? null : Icon(icon, size: 18),
                          label: Text(label),
                        ),
                    ],
                  ),
                  FutureBuilder(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) => Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        snapshot.data == null
                            ? ''
                            : 'Haneoka ${snapshot.data!.version} (${snapshot.data!.buildNumber})',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
