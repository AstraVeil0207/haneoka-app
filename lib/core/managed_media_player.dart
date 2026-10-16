import 'package:media_kit/media_kit.dart' as media;

import 'media_lifecycle.dart';

/// Native media ownership for preview/movie hosts using media_kit directly.
final class ManagedMediaPlayer extends media.Player {
  factory ManagedMediaPlayer({
    media.PlayerConfiguration configuration = const media.PlayerConfiguration(),
  }) {
    MediaLifecycle.requireOpen();
    return ManagedMediaPlayer._(configuration);
  }
  ManagedMediaPlayer._(media.PlayerConfiguration configuration)
    : super(configuration: configuration) {
    MediaLifecycle.register(this, dispose);
  }
  Future<void>? _disposing;
  @override
  Future<void> dispose() => _disposing ??= _dispose();
  Future<void> _dispose() async {
    await super.dispose();
    MediaLifecycle.unregister(this);
  }
}
