import '../core/managed_media_player.dart';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../ui/app_image.dart';

typedef MovieClip = ({String url, bool loop, bool backdrop});

/// The animated card's gacha movie (`videoSequence`): both anime parts,
/// then the Live2D intro and the showcase loop over the card background.
/// Starts on a tap, with the poster until then.
class CardMovie extends StatefulWidget {
  const CardMovie({
    super.key,
    required this.clips,
    required this.poster,
    this.background,
  });
  final List<MovieClip> clips;
  final String poster;
  final String? background;
  @override
  State<CardMovie> createState() => _CardMovieState();
}

class _CardMovieState extends State<CardMovie> {
  Player? _player;
  VideoController? _controller;
  int _index = 0;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final player = ManagedMediaPlayer();
    setState(() {
      _player = player;
      _controller = VideoController(player);
      _index = 0;
    });
    player.stream.completed.listen((done) {
      if (!done || !mounted || !identical(player, _player)) return;
      if (_index + 1 < widget.clips.length) _open(_index + 1);
    });
    await player.setVolume(0);
    if (!mounted || !identical(player, _player)) return;
    await _open(0);
  }

  Future<void> _open(int index) async {
    final player = _player;
    if (player == null) return;
    setState(() => _index = index);
    final clip = widget.clips[index];
    await player.setPlaylistMode(
      clip.loop ? PlaylistMode.single : PlaylistMode.none,
    );
    await player.open(Media(clip.url));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          AppImage(
            candidates: [widget.poster],
            fit: BoxFit.contain,
            localized: false,
          ),
          Center(
            child: IconButton.filled(
              iconSize: 40,
              onPressed: _start,
              icon: const Icon(Symbols.play_arrow_rounded),
            ),
          ),
        ],
      );
    }
    final clip = widget.clips[_index];
    return Stack(
      fit: StackFit.expand,
      children: [
        if (clip.backdrop && widget.background != null)
          AppImage(
            candidates: [widget.background!],
            fit: BoxFit.cover,
            localized: false,
          ),
        Video(
          controller: controller,
          fill: clip.backdrop ? Colors.transparent : Colors.black,
          controls: NoVideoControls,
        ),
      ],
    );
  }
}
