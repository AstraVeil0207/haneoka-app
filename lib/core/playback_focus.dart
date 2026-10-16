import 'dart:async';

/// Serializes ownership across music and page media, outside their transport
/// queues. Each owner keeps its own queue, metadata and lifecycle.
final class PlaybackFocus {
  PlaybackFocus(Future<void> Function() interrupt) : _interrupt = interrupt;
  final Future<void> Function() _interrupt;
  static PlaybackFocus? _active;
  static Future<void> _requests = Future.value();
  bool _closed = false;

  Future<void> activate(Future<void> Function() start) {
    final request = _requests.then((_) async {
      if (_closed) return;
      final previous = _active;
      if (previous != null && !identical(previous, this)) {
        await previous._interrupt();
      }
      if (_closed) return;
      _active = this;
      try {
        await start();
      } catch (_) {
        if (identical(_active, this)) _active = null;
        rethrow;
      }
    });
    _requests = request.catchError((Object _) {});
    return request;
  }

  void close() {
    _closed = true;
    if (identical(_active, this)) _active = null;
  }
}
