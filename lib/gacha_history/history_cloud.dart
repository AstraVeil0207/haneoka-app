import 'dart:convert';

import '../account/haneoka_account.dart';
import 'game_history_client.dart' show GameHistoryRegion;
import 'history_snapshot.dart';

const historyCloudBytes = 1024 * 1024;
final _accountKeyPattern = RegExp(r'^[a-f0-9]{64}$');

class HistoryCloudError implements Exception {
  const HistoryCloudError(this.code, [this.status = 0]);
  final String code;
  final int status;
  @override
  String toString() => code;
}

class HistoryCloudSummary {
  const HistoryCloudSummary({
    required this.accountKey,
    required this.server,
    required this.revision,
    required this.updatedAt,
    required this.refreshRequested,
    required this.refreshCompleted,
  });
  final String accountKey, server;
  final int revision, updatedAt, refreshRequested, refreshCompleted;
  bool get refreshPending => refreshRequested > refreshCompleted;

  factory HistoryCloudSummary.fromJson(Object? value) {
    if (value is! Map ||
        value['accountKey'] is! String ||
        !_accountKeyPattern.hasMatch(value['accountKey'] as String) ||
        !GameHistoryRegion.values.any(
          (region) => region.id == value['server'],
        )) {
      throw const HistoryCloudError('history_response_invalid');
    }
    final summary = HistoryCloudSummary(
      accountKey: value['accountKey'] as String,
      server: value['server'] as String,
      revision: _sequence(value['revision']),
      updatedAt: _sequence(value['updatedAt']),
      refreshRequested: _sequence(value['refreshRequested']),
      refreshCompleted: _sequence(value['refreshCompleted']),
    );
    if (summary.refreshCompleted > summary.refreshRequested) {
      throw const HistoryCloudError('history_response_invalid');
    }
    return summary;
  }
}

class HistoryCloudDocument {
  const HistoryCloudDocument({
    required this.ownerId,
    required this.summary,
    required this.histories,
  });
  final String ownerId;
  final HistoryCloudSummary summary;
  final List<HistorySnapshot> histories;
  String get accountKey => summary.accountKey;
  String get server => summary.server;
  int get revision => summary.revision;
  int get updatedAt => summary.updatedAt;
  int get refreshRequested => summary.refreshRequested;
  int get refreshCompleted => summary.refreshCompleted;
  bool get refreshPending => summary.refreshPending;

  factory HistoryCloudDocument.fromJson(
    Map value,
    String owner,
    String accountKey,
  ) {
    final summary = HistoryCloudSummary.fromJson(value);
    if (value['ownerId'] != owner || summary.accountKey != accountKey) {
      throw const HistoryCloudError('account_changed', 409);
    }
    final rows = value['histories'];
    if (rows is! List || rows.isEmpty) {
      throw const HistoryCloudError('history_response_invalid');
    }
    final kinds = <String>{}, histories = <HistorySnapshot>[];
    for (final row in rows) {
      final history = HistorySnapshot.fromJson(row).forAccount(accountKey);
      if (history.server != summary.server || !kinds.add(history.historyKind)) {
        throw const HistoryCloudError('history_response_invalid');
      }
      histories.add(history);
    }
    return HistoryCloudDocument(
      ownerId: owner,
      summary: summary,
      histories: List.unmodifiable(histories),
    );
  }
}

int _sequence(Object? value) {
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value > 9007199254740991 ||
      value != value.truncateToDouble()) {
    throw const HistoryCloudError('history_response_invalid');
  }
  return value.toInt();
}

/// Stateless transport over the existing Haneoka session. The caller owns
/// local persistence, scheduling and the canonical game-account fingerprint.
class HistoryCloudClient {
  HistoryCloudClient([HaneokaAccount? account])
    : _account = account ?? HaneokaAccount.instance;
  final HaneokaAccount _account;

  String? get _currentOwner {
    final id = _account.user?['id'];
    return _account.signedIn && id is String && id.isNotEmpty ? id : null;
  }

  String _owner() =>
      _currentOwner ??
      (throw const HistoryCloudError('authentication_required', 401));

  void _guard(String owner) {
    if (_currentOwner != owner) {
      throw const HistoryCloudError('account_changed', 409);
    }
  }

  Future<T> _owned<T>(String owner, Future<T> Function() action) async {
    _guard(owner);
    try {
      final value = await action();
      _guard(owner);
      return value;
    } catch (_) {
      _guard(owner);
      rethrow;
    }
  }

  Future<Map> _request(
    String owner,
    String method,
    String? accountKey, {
    String suffix = '',
    Map<String, Object?>? body,
  }) async {
    if (accountKey != null && !_accountKeyPattern.hasMatch(accountKey)) {
      throw const HistoryCloudError('history_account_key_invalid');
    }
    if (body != null &&
        utf8.encode(jsonEncode(body)).length > historyCloudBytes) {
      throw const HistoryCloudError('history_too_large', 413);
    }
    final value = await _owned(
      owner,
      () => _account
          .request(
            method,
            '/api/v1/gacha-history${accountKey == null ? '' : '/$accountKey'}$suffix',
            body: body,
            headers: {'X-Haneoka-Expected-User': owner},
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () =>
                throw const HistoryCloudError('history_network_error'),
          ),
    );
    _guard(owner);
    if (value is! Map || value['ownerId'] != owner) {
      throw const HistoryCloudError('account_changed', 409);
    }
    return value;
  }

  Future<List<HistoryCloudSummary>> list() async {
    final owner = _owner();
    final value = await _request(owner, 'GET', null);
    _guard(owner);
    final rows = value['accounts'];
    if (rows is! List) {
      throw const HistoryCloudError('history_response_invalid');
    }
    return List.unmodifiable(rows.map(HistoryCloudSummary.fromJson));
  }

  Future<HistoryCloudDocument> _read(String owner, String accountKey) async {
    final value = await _request(owner, 'GET', accountKey);
    _guard(owner);
    return HistoryCloudDocument.fromJson(value, owner, accountKey);
  }

  Future<HistoryCloudDocument> read(String accountKey) =>
      _read(_owner(), accountKey);

  Future<HistoryCloudDocument> _upload(
    String owner,
    String accountKey,
    HistorySnapshot history,
    int completedRequest,
  ) async {
    _guard(owner);
    if (completedRequest < 0 || completedRequest > 9007199254740991) {
      throw const HistoryCloudError('invalid_refresh');
    }
    final normalized = HistorySnapshot.fromJson(history.toJson())
        .forAccount(accountKey);
    final value = await _request(
      owner,
      'POST',
      accountKey,
      body: {
        'history': normalized.toJson(),
        'completedRequest': completedRequest,
      },
    );
    _guard(owner);
    return HistoryCloudDocument.fromJson(value, owner, accountKey);
  }

  Future<HistoryCloudDocument> upload(
    String accountKey,
    HistorySnapshot history, {
    int completedRequest = 0,
  }) => _upload(_owner(), accountKey, history, completedRequest);

  Future<HistoryCloudDocument> requestRefresh(String accountKey) async {
    final owner = _owner();
    final value = await _request(
      owner,
      'POST',
      accountKey,
      suffix: '/refresh',
      body: {},
    );
    _guard(owner);
    return HistoryCloudDocument.fromJson(value, owner, accountKey);
  }

  Future<HistoryCloudDocument> fulfillRefresh(
    String accountKey,
    Future<HistorySnapshot> Function() readOfficial,
  ) async {
    final owner = _owner();
    final current = await _owned(owner, () => _read(owner, accountKey));
    final history = await _owned(owner, readOfficial);
    return _upload(owner, accountKey, history, current.refreshRequested);
  }
}
