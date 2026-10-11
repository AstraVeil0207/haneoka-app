import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_state.dart';
import '../shell/links.dart';
import '../shell/page.dart';
import '../ui/shapes.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';

const _repo = 'https://github.com/haneoka-gakuen/haneoka';
const _discord = 'https://discord.gg/GKU3bwS9sN';
const _qq = '754989697';
const _github =
    '<svg viewBox="0 0 24 24"><path fill="#000" d="M12 .3a12 12 0 0 0-3.8 23.38c.6.12.83-.26.83-.57v-2.23c-3.34.73-4.04-1.42-4.04-1.42-.55-1.39-1.33-1.76-1.33-1.76-1.09-.74.08-.73.08-.73 1.2.09 1.84 1.24 1.84 1.24 1.07 1.83 2.81 1.3 3.5 1 .1-.78.42-1.31.76-1.61-2.67-.3-5.47-1.33-5.47-5.93 0-1.31.47-2.38 1.24-3.22-.14-.3-.54-1.52.1-3.18 0 0 1-.32 3.3 1.23a11.5 11.5 0 0 1 6 0c2.28-1.55 3.29-1.23 3.29-1.23.64 1.66.24 2.88.12 3.18a4.65 4.65 0 0 1 1.23 3.22c0 4.61-2.8 5.63-5.48 5.92.42.36.81 1.1.81 2.22v3.29c0 .31.21.69.82.57A12 12 0 0 0 12 .3"/></svg>';
const _discordLogo =
    '<svg viewBox="0 0 24 24"><path fill="#000" d="M20.32 4.37a19.8 19.8 0 0 0-4.89-1.52.07.07 0 0 0-.08.04c-.21.38-.44.87-.61 1.25a18.27 18.27 0 0 0-5.49 0 12.64 12.64 0 0 0-.62-1.25.08.08 0 0 0-.08-.04 19.74 19.74 0 0 0-4.88 1.52.07.07 0 0 0-.03.03C.53 9.05-.32 13.58.1 18.06a.08.08 0 0 0 .03.06 19.9 19.9 0 0 0 5.99 3.03.08.08 0 0 0 .08-.03c.46-.63.87-1.3 1.23-1.99a.08.08 0 0 0-.04-.11 13.1 13.1 0 0 1-1.87-.9.08.08 0 0 1-.01-.13l.37-.29a.07.07 0 0 1 .08-.01c3.93 1.8 8.18 1.8 12.06 0a.07.07 0 0 1 .08.01l.37.29a.08.08 0 0 1-.01.13c-.6.35-1.22.65-1.87.9a.08.08 0 0 0-.04.11c.36.7.78 1.36 1.23 1.99a.08.08 0 0 0 .08.03 19.84 19.84 0 0 0 6-3.03.08.08 0 0 0 .03-.06c.5-5.18-.84-9.67-3.55-13.66a.06.06 0 0 0-.03-.03zM8.02 15.33c-1.18 0-2.16-1.08-2.16-2.42 0-1.33.96-2.42 2.16-2.42 1.21 0 2.18 1.1 2.16 2.42 0 1.34-.96 2.42-2.16 2.42zm7.97 0c-1.18 0-2.15-1.08-2.15-2.42 0-1.33.95-2.42 2.15-2.42 1.22 0 2.18 1.1 2.16 2.42 0 1.34-.94 2.42-2.16 2.42z"/></svg>';

/// The website's Join page (`JoinPage.astro`): how to give feedback and
/// where the players meet.
class JoinScreen extends StatelessWidget {
  const JoinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    String k(String key) => t('legal.join.$key');
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void open(String url) =>
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    Widget logo(String svg) => SvgPicture.string(
      svg,
      width: 28,
      height: 28,
      colorFilter: ColorFilter.mode(
        scheme.onSecondaryContainer,
        BlendMode.srcIn,
      ),
    );
    Widget section(String title, String body, List<Widget> cards) => Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 656 ? 2 : 1;
              final width =
                  (constraints.maxWidth - 16 * (columns - 1)) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final card in cards) SizedBox(width: width, child: card),
                ],
              );
            },
          ),
        ],
      ),
    );
    final mention = Row(
      children: [
        Icon(Symbols.info_rounded, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            k('mention'),
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
        ),
      ],
    );
    return ShellPage(
      title: k('title'),
      body: ListView(
        padding: pagePadding(context).add(const EdgeInsets.only(top: 16)),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 32,
                    runSpacing: 20,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ShapedIcon(
                        shape: MaterialShapes.cookie9Sided,
                        size: (MediaQuery.sizeOf(context).width * 0.12).clamp(
                          88.0,
                          128.0,
                        ),
                        color: scheme.primaryContainer,
                        foreground: scheme.onPrimaryContainer,
                        child: const Icon(Symbols.handshake_rounded, size: 40),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              k('eyebrow'),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              k('heroTitle'),
                              style: theme.textTheme.displaySmall,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              k('description'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w400,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  section(k('feedbackTitle'), k('feedbackBody'), [
                    _JoinCard(
                      icon: ShapedIcon(
                        shape: MaterialShapes.sunny,
                        child: logo(_github),
                      ),
                      title: k('githubTitle'),
                      body: k('githubBody'),
                      footer: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => open('$_repo/issues/new/choose'),
                            icon: const Icon(Symbols.error_rounded),
                            label: Text(k('githubIssues')),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => open('$_repo/pulls'),
                            icon: const Icon(Symbols.code_rounded),
                            label: Text(k('githubPulls')),
                          ),
                        ],
                      ),
                    ),
                    _JoinCard(
                      icon: ShapedIcon(
                        shape: _clover,
                        child: const Icon(Symbols.forum_rounded, size: 28),
                      ),
                      title: k('communityTitle'),
                      body: k('communityBody'),
                      footer: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (slug, icon, label) in [
                            (
                              'feedback',
                              Symbols.chat_rounded,
                              k('forumFeedback'),
                            ),
                            (
                              'bug-report',
                              Symbols.error_rounded,
                              k('forumBugs'),
                            ),
                            (
                              'new-feature-request',
                              Symbols.lightbulb_rounded,
                              k('forumFeatures'),
                            ),
                          ])
                            ActionChip(
                              avatar: Icon(icon, size: 18),
                              label: Text(label),
                              onPressed: () =>
                                  openLink(context, '/community/forums/$slug/'),
                            ),
                        ],
                      ),
                    ),
                  ]),
                  section(k('connectTitle'), k('connectBody'), [
                    _JoinCard(
                      accent: true,
                      icon: ShapedIcon(
                        shape: MaterialShapes.softBurst,
                        child: logo(_discordLogo),
                      ),
                      title: k('discordTitle'),
                      body: k('discordBody'),
                      note: mention,
                      footer: FilledButton.icon(
                        onPressed: () => open(_discord),
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Symbols.open_in_new_rounded),
                        label: Text(k('discordAction')),
                      ),
                    ),
                    _JoinCard(
                      accent: true,
                      icon: ShapedIcon(
                        shape: _flower,
                        child: const Icon(Symbols.groups_rounded, size: 28),
                      ),
                      title: k('qqTitle'),
                      body: k('qqBody'),
                      note: mention,
                      footer: Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            k('qqLabel'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            _qq,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              await Clipboard.setData(
                                const ClipboardData(text: _qq),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(k('copied'))),
                                );
                              }
                            },
                            icon: const Icon(Symbols.content_copy_rounded),
                            label: Text(k('copy')),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(Corner.extraLarge),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Symbols.handshake_rounded, color: scheme.primary),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                k('partnerTitle'),
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                k('partnerBody'),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

final _clover = MaterialShapes.clover4Leaf;
final _flower = MaterialShapes.flower;

class _JoinCard extends StatelessWidget {
  const _JoinCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.footer,
    this.note,
    this.accent = false,
  });
  final Widget icon;
  final String title;
  final String body;
  final Widget? note;
  final Widget footer;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 20 : 28,
        vertical: compact ? 24 : 28,
      ),
      decoration: BoxDecoration(
        color: accent ? scheme.surfaceContainerHigh : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(Corner.extraLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          if (note != null) ...[const SizedBox(height: 12), note!],
          const SizedBox(height: 16),
          footer,
        ],
      ),
    );
  }
}
