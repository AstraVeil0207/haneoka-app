import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../core/net.dart';
import '../save/game_save.dart';
import '../save/save_view.dart';

const _origin = 'https://haneoka.org';
const _tokenKey = 'haneoka-session';

/// A player linked to the Haneoka account (`community_game_account`).
class LinkedPlayer {
  const LinkedPlayer({
    required this.server,
    required this.profileId,
    required this.visibility,
    this.name,
    this.syncedAt,
  });
  final String server;
  final String profileId;
  final String? name;
  final String visibility;
  final DateTime? syncedAt;

  bool get public => visibility == 'public';

  static LinkedPlayer? fromJson(Object? json) {
    if (json is! Map) return null;
    final synced = json['lastSyncedAt'];
    return LinkedPlayer(
      server: '${json['region']}',
      profileId: '${json['playerUid']}',
      name: json['displayName'] as String?,
      visibility: '${json['visibility'] ?? 'private'}',
      syncedAt: synced is num
          ? DateTime.fromMillisecondsSinceEpoch(synced.toInt())
          : null,
    );
  }
}

/// Why a request to the account API failed.
class AccountError implements Exception {
  const AccountError(this.code);
  final String code;
  @override
  String toString() => 'AccountError($code)';
}

/// The reader's Haneoka account in the app: a session of its own, obtained
/// through the website's sign-in (`/account/app/`, PKCE) and sent as a bearer
/// token, plus the Our Notes players linked to it.
class HaneokaAccount extends ChangeNotifier {
  HaneokaAccount._();
  static final HaneokaAccount instance = HaneokaAccount._();

  static const _storage = FlutterSecureStorage();

  String? _token;
  Map<String, Object?>? _user;
  List<LinkedPlayer> _players = const [];
  bool _loaded = false;

  bool get signedIn => _token != null && _user != null;
  Map<String, Object?>? get user => _user;
  List<LinkedPlayer> get players => _players;

  LinkedPlayer? linkOf(GameSave save) => _players
      .where(
        (p) =>
            p.server == save.release?.server && p.profileId == save.profileId,
      )
      .firstOrNull;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _token = await _storage.read(key: _tokenKey);
    } catch (_) {
      _token = null;
    }
    if (_token == null) return;
    await refresh();
  }

  /// Reads the session and the linked players again.
  Future<void> refresh() async {
    if (_token == null) return;
    try {
      final session = await _request('GET', '/api/auth/get-session');
      final user = (session as Map?)?['user'];
      if (user is! Map) {
        await _forget();
        return;
      }
      _user = user.cast<String, Object?>();
      try {
        final profile = (await _request(
          'GET',
          '/api/v1/account/profile',
        ) as Map?)?['profile'];
        if (profile is Map) {
          _user = {
            ..._user!,
            'uid': profile['publicUid'],
            if (profile['displayName'] case final String name
                when name.isNotEmpty)
              'name': name,
            if (profile['avatarUrl'] case final String avatar) 'image': avatar,
          };
        }
      } on AccountError {
        // A profile not set up yet still signs in.
      }
      await _readPlayers();
    } on AccountError catch (error) {
      if (error.code == 'unauthenticated') await _forget();
    } catch (_) {
      // Offline: keep the stored session for next time.
    }
    notifyListeners();
  }

  Future<void> signIn(String locale) async {
    final random = Random.secure();
    String token(int bytes) => base64Url
        .encode(List.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    final verifier = token(48);
    final state = token(16);
    final challenge = challengeOf(verifier);
    final query = <String, String>{'challenge': challenge, 'state': state};
    var scheme = 'haneoka';
    // Desktop builds receive the code on a loopback listener (RFC 8252).
    if (Platform.isLinux || Platform.isWindows) {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      scheme = 'http://127.0.0.1:$port';
      query['redirect'] = '$scheme/auth';
    }
    final result = await FlutterWebAuth2.authenticate(
      url: Uri.parse('$_origin/$locale/account/app/')
          .replace(queryParameters: query)
          .toString(),
      callbackUrlScheme: scheme,
    );
    final callback = Uri.parse(result).queryParameters;
    if (callback['state'] != state) throw const AccountError('invalid_state');
    final code = callback['code'];
    if (code == null) throw AccountError(callback['error'] ?? 'cancelled');
    final body = await _request(
      'POST',
      '/api/v1/account/app/token',
      body: {'code': code, 'verifier': verifier},
      authorized: false,
    );
    final session = (body as Map?)?['token'];
    if (session is! String) throw const AccountError('invalid_grant');
    _token = session;
    try {
      await _storage.write(key: _tokenKey, value: session);
    } catch (_) {
      // Without a keychain the session lasts until the app closes.
    }
    await refresh();
  }

  Future<void> signOut() async {
    try {
      await _request('POST', '/api/auth/sign-out', body: const {});
    } catch (_) {
      // The session is forgotten here either way.
    }
    await _forget();
    notifyListeners();
  }

  /// Links [save]'s player, or updates its summary and visibility.
  Future<void> link(GameSave save, {bool? public}) async {
    final view = SaveView(save);
    final current = linkOf(save);
    final body = await _request(
      'PUT',
      '/api/v1/account/game-accounts',
      body: {
        'server': save.release?.server,
        'profileId': save.profileId,
        'name': save.name,
        'visibility': (public ?? current?.public ?? true)
            ? 'public'
            : 'private',
        'savedAt': save.modifiedAt?.millisecondsSinceEpoch,
        'summary': summaryOf(view),
      },
    );
    _readPlayersFrom(body);
  }

  /// Updates an already linked player after a new import.
  Future<void> syncIfLinked(GameSave save) async {
    if (!signedIn || linkOf(save) == null) return;
    try {
      await link(save);
    } catch (_) {
      // The next update from the player's page retries.
    }
  }

  Future<void> unlink(GameSave save) async {
    final body = await _request(
      'DELETE',
      '/api/v1/account/game-accounts/${save.release?.server}/${save.profileId}',
    );
    _readPlayersFrom(body);
  }

  /// The public numbers a linked player shows; never the save itself.
  static Map<String, Object?> summaryOf(SaveView view) {
    int count(String difficulty, int threshold) => view
        .rows(SaveSection.songs)
        .where(
          (row) =>
              ((row['_${difficulty}ClearedStatus'] as num?) ?? 0) >= threshold,
        )
        .length;
    final started = view.player['_tutorialFinishedAtUnixSeconds'];
    return {
      'rank': view.playerRank,
      'exp': view.exp,
      'rating': view.highScoreRating,
      'members': view.rows(SaveSection.memberCards).length,
      'snapshots': view.rows(SaveSection.snapshots).length,
      'favoriteMemberCardId': view.favoriteMemberCardId,
      'startedAt': started is num && started > 0 ? started.toInt() : null,
      'clears': {
        for (final difficulty in const ['easy', 'normal', 'hard', 'expert'])
          difficulty: [
            count(difficulty, 10),
            count(difficulty, 20),
            count(difficulty, 30),
          ],
      },
    };
  }

  Future<void> _readPlayers() async =>
      _readPlayersFrom(await _request('GET', '/api/v1/account/game-accounts'));

  void _readPlayersFrom(Object? body) {
    _players = [
      for (final row in ((body as Map?)?['accounts'] as List? ?? const []))
        ?LinkedPlayer.fromJson(row),
    ];
    notifyListeners();
  }

  Future<void> _forget() async {
    _token = null;
    _user = null;
    _players = const [];
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {}
  }

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    bool authorized = true,
  }) async {
    final request = http.Request(method, Uri.parse('$_origin$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        'Origin': _origin,
        if (authorized && _token != null) 'Authorization': 'Bearer $_token',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await netClient.send(request),
    );
    final text = utf8.decode(response.bodyBytes);
    final json = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode == 401) throw const AccountError('unauthenticated');
    if (response.statusCode >= 400) {
      final error = (json as Map?)?['error'];
      throw AccountError(
        error is Map ? '${error['code']}' : 'http_${response.statusCode}',
      );
    }
    return json;
  }

  @visibleForTesting
  static String challengeOf(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');
}
