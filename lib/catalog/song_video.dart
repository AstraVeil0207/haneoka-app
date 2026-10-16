import '../core/managed_media_player.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/app_state.dart';
import '../ui/app_image.dart';
import '../ui/detail.dart';
import '../ui/theme.dart';

/// A song's music videos (`.song-detail-mv-section`): the jacket as poster
/// until Play, then the video with its controls; a segmented choice when the
/// song has more than one.
class SongVideos extends StatefulWidget {
  const SongVideos({super.key, required this.song});
  final Map<String, Object?> song;

  /// The song's videos: `musicVideos`, else its single `mvUrl`.
  static List<Map> of(Map song) => switch (song['musicVideos']) {
    final Map videos when videos.isNotEmpty => [
      for (final video in videos.values.whereType<Map>())
        if (video['playableUrl'] case final String url when url.isNotEmpty)
          video,
    ],
    final List videos when videos.isNotEmpty => [
      for (final video in videos.whereType<Map>())
        if (video['playableUrl'] case final String url when url.isNotEmpty)
          video,
    ],
    _ => [
      if (song['mvUrl'] case final String url when url.isNotEmpty)
        {'playableUrl': url, 'title': 'MV'},
    ],
  };

  @override
  State<SongVideos> createState() => _SongVideosState();
}

class _SongVideosState extends State<SongVideos> {
  int _index = 0;
  Player? _player;
  VideoController? _controller;
  String? _error;
  final _subscriptions = <StreamSubscription<dynamic>>[];

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _player?.dispose();
    _player = null;
    _controller = null;
  }

  Future<void> _play(String url) async {
    final state = AppScope.of(context);
    final source = state.api.asset(url).toString();
    await state.audio.pause();
    if (!mounted) return;
    _stop();
    final player = ManagedMediaPlayer();
    setState(() {
      _player = player;
      _controller = VideoController(player);
      _error = null;
    });
    _subscriptions.add(
      player.stream.completed.listen((done) {
        if (done && mounted && identical(_player, player)) setState(_stop);
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((error) {
        if (!mounted || !identical(_player, player)) return;
        setState(() {
          _stop();
          _error = error;
        });
      }),
    );
    try {
      await player.open(Media(source));
    } catch (error) {
      if (mounted && identical(_player, player)) {
        setState(() {
          _stop();
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = state.text;
    final scheme = Theme.of(context).colorScheme;
    final videos = SongVideos.of(widget.song);
    if (videos.isEmpty) return const SizedBox.shrink();
    final index = _index.clamp(0, videos.length - 1);
    final jacket = widget.song['jacketUrl'];
    final controller = _controller;
    return DetailSection(
      icon: Symbols.movie_rounded,
      title: t.label('mv', 'MV'),
      count: videos.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(t('common.states.unavailable', 'Unavailable')),
            ),
          if (videos.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (final (i, video) in videos.indexed)
                    ButtonSegment(
                      value: i,
                      label: Text(
                        t.text(video['title']).isEmpty
                            ? 'MV ${i + 1}'
                            : t.text(video['title']),
                      ),
                    ),
                ],
                selected: {index},
                onSelectionChanged: (value) => setState(() {
                  _stop();
                  _index = value.single;
                }),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(Corner.large),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Corner.large),
                  child: controller != null
                      ? Video(controller: controller)
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            if (jacket is String && jacket.isNotEmpty)
                              AppImage(
                                candidates: [
                                  state.api.asset(jacket).toString(),
                                ],
                                fit: BoxFit.cover,
                              ),
                            ColoredBox(
                              color: Colors.black.withValues(alpha: 0.32),
                            ),
                            Center(
                              child: IconButton.filled(
                                iconSize: 32,
                                padding: const EdgeInsets.all(16),
                                tooltip:
                                    '${t('common.actions.play', 'Play')} ${t.label('mv', 'MV')}',
                                onPressed: () =>
                                    _play('${videos[index]['playableUrl']}'),
                                icon: const Icon(Symbols.play_arrow_rounded),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
