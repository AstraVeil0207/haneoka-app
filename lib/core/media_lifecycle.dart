/// Host IO owners register their real asynchronous close operation. Rendering,
/// source policy and storage stay outside this application shutdown boundary.
final class MediaLifecycle {
  MediaLifecycle._();
  static final _owners = <Object, Future<void> Function()>{};
  static Future<void>? _drain;
  static bool _shutdown = false;
  static bool get draining => _shutdown;
  static int get ownerCount => _owners.length;
  static void requireOpen() {
    if (draining) {
      throw StateError('media_shutdown_active');
    }
  }

  static void register(Object owner, Future<void> Function() close) {
    requireOpen();
    _owners[owner] = close;
  }

  static void unregister(Object owner) => _owners.remove(owner);
  static Future<void> drain() {
    _shutdown = true;
    return _drain ??= _drainOwners();
  }

  static Future<void> _drainOwners() async {
    while (_owners.isNotEmpty) {
      await Future.wait([for (final close in _owners.values.toList()) close()]);
    }
  }
}
