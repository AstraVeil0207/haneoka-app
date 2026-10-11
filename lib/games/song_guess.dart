import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../shell/links.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';

class _Song {
  const _Song(this.id, this.title, this.bandId, this.jacket);
  final int id;
  final String title;
  final int bandId;
  final String jacket;
}

class _Round {
  _Round(this.answer, this.options, this.focus);
  final _Song answer;
  final List<_Song> options;
  final Offset focus;
  final List<int> misses = [];
  bool solved = false;
}

/// Zoom per wrong answer: the crop widens until the whole jacket shows.
const _zooms = [6.0, 3.5, 2.0, 1.0];

/// Name the song from a crop of its jacket; every miss widens the crop
/// (`song-guess`).
class SongGuessScreen extends StatefulWidget {
  const SongGuessScreen({super.key});
  @override
  State<SongGuessScreen> createState() => _SongGuessScreenState();
}

class _SongGuessScreenState extends State<SongGuessScreen> {
  final _random = Random();
  Future<List<_Song>>? _songs;
  _Round? _round;
  String _pool = 'all';
  int _played = 0, _firstTry = 0, _streak = 0, _best = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _songs ??= _load();
  }

  Future<List<_Song>> _load() async {
    final state = AppScope.of(context);
    final document = await state.api.catalog('songs');
    final rows = document is Map && document['items'] is Map
        ? document['items'] as Map
        : document as Map;
    final songs =
        [
              for (final song in rows.values.whereType<Map>())
                _Song(
                  (song['musicId'] as num?)?.toInt() ?? 0,
                  state.songTitle(song['musicTitle']),
                  (song['bandId'] as num?)?.toInt() ?? 0,
                  '${song['jacketUrl'] ?? song['jacketThumbUrl'] ?? ''}',
                ),
            ]
            .where((s) => s.id > 0 && s.jacket.isNotEmpty && s.title.isNotEmpty)
            .toList();
    _next(songs);
    return songs;
  }

  T _pick<T>(List<T> rows) => rows[_random.nextInt(rows.length)];

  void _next(List<_Song> songs) {
    if (songs.length < 4) return;
    final answer = _pick(songs);
    final pool = _pool == 'band'
        ? songs.where((s) => s.bandId == answer.bandId).toList()
        : songs;
    final others = (pool.length >= 4 ? pool : songs)
        .where((s) => s.id != answer.id)
        .toList();
    final options = [answer];
    while (options.length < 4) {
      final candidate = _pick(others);
      if (!options.contains(candidate)) options.add(candidate);
    }
    options.shuffle(_random);
    _round = _Round(
      answer,
      options,
      Offset(
        0.1 + _random.nextDouble() * 0.8,
        0.1 + _random.nextDouble() * 0.8,
      ),
    );
  }

  void _choose(_Song song) {
    final round = _round;
    if (round == null || round.solved || round.misses.contains(song.id)) return;
    setState(() {
      if (song.id == round.answer.id) {
        _played++;
        if (round.misses.isEmpty) {
          _firstTry++;
          _streak++;
          _best = max(_best, _streak);
        } else {
          _streak = 0;
        }
        round.solved = true;
      } else {
        round.misses.add(song.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    String text(String key, String fallback) =>
        t('catalog.songGuess.$key', fallback);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final number = NumberFormat.decimalPattern(t.locale);
    return ShellPage(
      title: text('title', 'Guess the song'),
      body: FutureBuilder(
        future: _songs,
        builder: (context, snapshot) {
          final songs = snapshot.data;
          final round = _round;
          if (songs == null || round == null) {
            return Center(
              child: snapshot.hasError
                  ? FilledButton.tonal(
                      onPressed: () => setState(() => _songs = _load()),
                      child: Text(t('common.actions.retry', 'Retry')),
                    )
                  : const CircularProgressIndicator(),
            );
          }
          final zoom = round.solved
              ? 1.0
              : _zooms[min(round.misses.length, _zooms.length - 1)];
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 840;
              final narrow = constraints.maxWidth < 600;
              final stage = Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Corner.extraLarge),
                child: Padding(
                  padding: EdgeInsets.all(narrow ? 16 : 24),
                  child: Column(
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Corner.large),
                            child: ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(end: zoom),
                                duration: Durations.medium2,
                                curve: Easing.emphasizedDecelerate,
                                builder: (context, value, child) =>
                                    Transform.scale(
                                      scale: value,
                                      alignment: Alignment(
                                        round.focus.dx * 2 - 1,
                                        round.focus.dy * 2 - 1,
                                      ),
                                      child: child,
                                    ),
                                child: AppImage(
                                  candidates: [
                                    state.api
                                        .asset(round.answer.jacket)
                                        .toString(),
                                  ],
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: narrow ? 1 : 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: narrow ? 380 / 56 : 300 / 56,
                        children: [
                          for (final song in round.options)
                            Builder(
                              builder: (context) {
                                final correct =
                                    round.solved && song.id == round.answer.id;
                                final wrong = round.misses.contains(song.id);
                                return OutlinedButton(
                                  onPressed: round.solved || wrong
                                      ? null
                                      : () => _choose(song),
                                  style: OutlinedButton.styleFrom(
                                    alignment: AlignmentDirectional.centerStart,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        Corner.large,
                                      ),
                                    ),
                                    side: BorderSide(
                                      color: correct
                                          ? Colors.transparent
                                          : scheme.outlineVariant,
                                    ),
                                    backgroundColor: correct
                                        ? scheme.primaryContainer
                                        : wrong
                                        ? scheme.surfaceContainer
                                        : scheme.surface,
                                    disabledForegroundColor: correct
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                                    foregroundColor: scheme.onSurface,
                                  ),
                                  child: Row(
                                    children: [
                                      if (correct || wrong) ...[
                                        Icon(
                                          correct
                                              ? Symbols.check_circle_rounded
                                              : Symbols.close_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Expanded(
                                        child: Text(
                                          song.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                decoration: wrong
                                                    ? TextDecoration.lineThrough
                                                    : null,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          if (round.solved)
                            Flexible(
                              child: TextButton.icon(
                                onPressed: () => openLink(
                                  context,
                                  '/${state.server}/${t.locale}/songs/${round.answer.id}/',
                                ),
                                icon: const Icon(
                                  Symbols.library_music_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  round.answer.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: () => setState(() => _next(songs)),
                            icon: Icon(
                              round.solved
                                  ? Symbols.arrow_forward_rounded
                                  : Symbols.skip_next_rounded,
                              size: 18,
                            ),
                            label: Text(
                              round.solved
                                  ? text('next', 'Next')
                                  : text('skip', 'Skip'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
              final panel = Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Corner.extraLarge),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: 'all',
                            label: Text(text('anyBand', 'All songs')),
                          ),
                          ButtonSegment(
                            value: 'band',
                            label: Text(text('sameBand', 'Same band')),
                          ),
                        ],
                        selected: {_pool},
                        onSelectionChanged: (v) => setState(() {
                          _pool = v.single;
                          _next(songs);
                        }),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        runSpacing: 12,
                        children: [
                          for (final (label, value) in [
                            (text('played', 'Played'), _played),
                            (text('firstTry', 'First try'), _firstTry),
                            (text('streak', 'Streak'), _streak),
                            (text('best', 'Best streak'), _best),
                          ])
                            FractionallySizedBox(
                              widthFactor: 0.5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(label, style: theme.textTheme.bodySmall),
                                  Text(
                                    number.format(value),
                                    style: theme.textTheme.titleLarge,
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
              return ListView(
                padding: pagePadding(context),
                children: [
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: stage),
                        const SizedBox(width: 24),
                        SizedBox(width: 340, child: panel),
                      ],
                    )
                  else ...[
                    stage,
                    const SizedBox(height: 24),
                    panel,
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}
