import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/app_state.dart';
import '../core/audio.dart';
import 'app_image.dart';
import 'theme.dart';

String _clock(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// The collapsed player (`now-playing`): the cover inside a ring showing how
/// much has played. It sits in the title bar on phones and in the navigation
/// elsewhere; tapping it opens the full player.
class NowPlaying extends StatelessWidget {
  const NowPlaying({super.key, this.expanded = false});

  /// The drawer's version adds the title, artist and play/pause.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final audio = AppScope.of(context).audio;
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final track = audio.current;
        if (track == null) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final cover = _Ring(
          audio: audio,
          track: track,
          size: expanded ? 52 : 40,
        );
        if (!expanded) {
          return IconButton(
            tooltip: track.title,
            onPressed: () => showPlayer(context),
            icon: cover,
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Corner.large),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => showPlayer(context),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    cover,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            track.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: audio.playing ? audio.pause : audio.resume,
                      icon: Icon(
                        audio.playing
                            ? Symbols.pause_rounded
                            : Symbols.play_arrow_rounded,
                        fill: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.audio, required this.track, required this.size});
  final AudioService audio;
  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder(
            valueListenable: audio.position,
            builder: (context, position, _) {
              final total = audio.duration.value.inMilliseconds;
              return CircularProgressIndicator(
                value: total == 0 ? 0 : position.inMilliseconds / total,
                strokeWidth: 3,
                backgroundColor: scheme.surfaceContainerHighest,
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(5),
            child: ClipOval(
              child: ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: track.artwork == null
                    ? Icon(
                        Symbols.music_note_rounded,
                        color: scheme.onSurfaceVariant,
                      )
                    : AppImage(candidates: [track.artwork!], fit: BoxFit.cover),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full player as the website's compact bottom sheet: large artwork,
/// title, the seek row with times, a 96 dp play button and the queue
/// controls.
Future<void> showPlayer(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 560),
  builder: (context) => const _FullPlayer(),
);

class _FullPlayer extends StatelessWidget {
  const _FullPlayer();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final audio = state.audio;
    final t = state.text;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final track = audio.current;
        if (track == null) return const SizedBox(height: 120);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.4,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Corner.extraLarge),
                    child: ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: track.artwork == null
                          ? null
                          : AppImage(
                              candidates: [track.artwork!],
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
              Text(
                track.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder(
                valueListenable: audio.position,
                builder: (context, position, _) {
                  final total = audio.duration.value;
                  final max = total.inMilliseconds.toDouble().clamp(
                    1.0,
                    double.infinity,
                  );
                  return Column(
                    children: [
                      Slider(
                        value: position.inMilliseconds.toDouble().clamp(0, max),
                        max: max,
                        onChanged: (value) =>
                            audio.seek(Duration(milliseconds: value.round())),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _clock(position),
                              style: theme.textTheme.labelMedium,
                            ),
                            Text(
                              _clock(total),
                              style: theme.textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: t('common.actions.close', 'Close'),
                    onPressed: () {
                      audio.stop();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Symbols.close_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: t('common.actions.previous', 'Previous'),
                    iconSize: 32,
                    onPressed: audio.previous,
                    icon: const Icon(Symbols.skip_previous_rounded, fill: 1),
                  ),
                  const SizedBox(width: 16),
                  SizedBox.square(
                    dimension: 96,
                    child: IconButton.filled(
                      tooltip: t(
                        audio.playing
                            ? 'common.actions.pause'
                            : 'common.actions.play',
                      ),
                      iconSize: 48,
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            audio.playing ? Corner.extraLarge : 48,
                          ),
                        ),
                      ),
                      onPressed: audio.playing ? audio.pause : audio.resume,
                      icon: Icon(
                        audio.playing
                            ? Symbols.pause_rounded
                            : Symbols.play_arrow_rounded,
                        fill: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    tooltip: t('common.actions.next', 'Next'),
                    iconSize: 32,
                    onPressed: audio.hasNext ? audio.next : null,
                    icon: const Icon(Symbols.skip_next_rounded, fill: 1),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
