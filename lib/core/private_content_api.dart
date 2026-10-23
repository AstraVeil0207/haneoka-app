import 'dart:async';

import '../account/haneoka_account.dart';
import 'account_resource.dart';
import 'api.dart';

/// Authorized release documents stay in the current native account's memory.
class PrivateContentApi extends HaneokaApi {
  PrivateContentApi({required super.server}) : super(eagerRelease: false) {
    _changes = AccountResources.instance.changes.listen((_) {
      _generation++;
      _release = null;
      _source = null;
      _opening = null;
      _documents.clear();
      HaneokaApi.clearResourceViews();
      _revision++;
      notifyListeners();
    });
  }
  final _account = HaneokaAccount.instance;
  late final StreamSubscription<void> _changes;
  final _documents = <String, Future<Object?>>{};
  String? _release, _source;
  Future<String>? _opening;
  int _generation = 0, _revision = 0;
  bool _disposed = false;
  DateTime? _checkedAt;
  @override
  int get revision => _revision;
  @override
  String? get sourceId => _source;
  Future<String> _identity() async {
    if (_disposed) throw StateError('source_closed');
    final generation = _generation;
    final value = objectOf(
      await _account
          .request('GET', '/api/v1/servers/$server/release?projection=identity')
          .timeout(const Duration(seconds: 30)),
    );
    if (generation != _generation) throw const AccountError('account_changed');
    final release = value['releaseId'] as String;
    if (_release != release || _source != value['sourceId']) {
      _documents.clear();
      HaneokaApi.clearResourceViews();
      _revision++;
    }
    _checkedAt = DateTime.now();
    _release = release;
    _source = value['sourceId'] as String?;
    return release;
  }

  @override
  Future<String> release() {
    if (_disposed) throw StateError('source_closed');
    if (_release != null &&
        _checkedAt != null &&
        DateTime.now().difference(_checkedAt!) < const Duration(minutes: 1)) {
      return Future.value(_release);
    }
    final existing = _opening;
    if (existing != null) return existing;
    final pending = () async {
      await _account.load();
      return await _identity();
    }();
    _opening = pending;
    unawaited(
      pending.then<void>(
        (_) {
          if (identical(_opening, pending)) _opening = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_opening, pending)) _opening = null;
        },
      ),
    );
    return pending;
  }

  @override
  Uri asset(String path) {
    final uri = Uri.parse(origin).resolve(path);
    return _release != null &&
            const {'http', 'https'}.contains(uri.scheme) &&
            uri.origin == Uri.parse(origin).origin &&
            (uri.path.startsWith('/assets/$server/') ||
                uri.path.startsWith('/runtime/$server/'))
        ? uri.replace(
            queryParameters: {...uri.queryParameters, 'release': _release!},
          )
        : uri;
  }

  @override
  Future<Object?> json(String path) async {
    final generation = _generation;
    final release = await this.release(), uri = Uri.parse(origin).resolve(path);
    final target = uri.replace(
      queryParameters: {...uri.queryParameters, 'release': release},
    );
    final key = target.toString();
    final cached = _documents[key];
    if (cached != null) return cached;
    late Future<Object?> request;
    request = _account
        .request(
          'GET',
          target.path + (target.hasQuery ? '?${target.query}' : ''),
        )
        .timeout(const Duration(seconds: 30))
        .then((value) {
          if (generation != _generation) {
            throw const AccountError('account_changed');
          }
          return value;
        })
        .catchError((Object error, StackTrace stack) {
          if (identical(_documents[key], request)) _documents.remove(key);
          Error.throwWithStackTrace(error, stack);
        });
    _documents[key] = request;
    return request;
  }

  @override
  Future<void> revalidate() async {
    await _identity();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _documents.clear();
    unawaited(_changes.cancel());
    HaneokaApi.clearResourceViews();
    super.dispose();
  }
}
