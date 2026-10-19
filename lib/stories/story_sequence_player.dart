import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../rendering/native_story_player_screen.dart';
import 'story_sequence.dart';

/// The reader and deep links use the same app-owned sequence host. Keeping its
/// route stable lets Back return to the page that opened the player.
class StorySequencePlayer extends StatefulWidget {
  const StorySequencePlayer({
    super.key,
    required this.storyId,
    this.server,
    this.api,
    this.title,
    this.catalog,
    this.textModeBuilder,
  });
  final String storyId;
  final String? server;
  final HaneokaApi? api;
  final Object? title;
  final Map? catalog;
  final Widget Function(BuildContext, String)? textModeBuilder;

  @override
  State<StorySequencePlayer> createState() => _StorySequencePlayerState();
}

class _StorySequencePlayerState extends State<StorySequencePlayer> {
  StorySequenceController? _sequence;
  HaneokaApi? _api;
  String? _server;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final server = widget.server ?? state.server;
    final api = widget.api ?? state.apiFor(server);
    if (_sequence != null && identical(_api, api) && _server == server) return;
    _sequence?.dispose();
    _api = api;
    _server = server;
    _sequence = StorySequenceController(
      currentId: widget.storyId,
      loadCatalog: () async {
        final supplied = widget.catalog;
        if (supplied != null &&
            StorySequenceCatalog(supplied).sequence(widget.storyId) != null) {
          return supplied;
        }
        // The same cached, release-pinned metadata projection as the web list.
        final value = await api.json(
          '/api/v1/servers/$server/stories?projection=4',
        );
        if (value is! Map) {
          throw const FormatException('story_sequence_catalog');
        }
        return value;
      },
      onInterrupt: () async {
        if (!mounted) return;
        final navigator = Navigator.of(context);
        if (await navigator.maybePop() || !mounted) return;
        final builder = widget.textModeBuilder;
        if (builder != null) {
          final id = _sequence!.currentId;
          await navigator.pushReplacement<void, void>(
            MaterialPageRoute<void>(
              settings: RouteSettings(
                name: Uri(
                  pathSegments: ['', 'stories', id],
                  queryParameters: {'server': server},
                ).toString(),
              ),
              builder: (context) => builder(context, id),
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _sequence?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sequence = _sequence!;
    return ListenableBuilder(
      listenable: sequence,
      builder: (context, _) => NativeStoryPlayerScreen(
        storyId: sequence.currentId,
        api: _api,
        server: _server,
        title:
            sequence.current?['title'] ??
            (sequence.currentId == widget.storyId ? widget.title : null),
        sequence: sequence,
        startAutomatically: sequence.startAutomatically,
        initialAutoAdvance: sequence.automatic,
        replaceTextMode: sequence.currentId != widget.storyId,
        textModeBuilder: widget.textModeBuilder == null
            ? null
            : (context) => widget.textModeBuilder!(context, sequence.currentId),
      ),
    );
  }
}
