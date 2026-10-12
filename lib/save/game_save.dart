import 'dart:typed_data';

import 'codec.dart';

/// Which release a save belongs to. Android packages and iOS bundle IDs share
/// these names.
enum GameRelease {
  intlOfficial('com.bilibili.sirius.official', 'intl'),
  intlStore('com.bilibili.sirius', 'intl'),
  jp('com.bushiroad.sirius', 'jp');

  const GameRelease(this.packageId, this.server);
  final String packageId;
  final String server;

  static GameRelease? fromPackage(String id) {
    for (final release in values) {
      if (release.packageId == id) return release;
    }
    return null;
  }
}

/// The three documents the game keeps per account.
enum SaveDocumentKind {
  /// `LocalCacheData`: settings plus `_player`, the account's progress.
  cache,

  /// `LocalPersistData`: latest live result, story resume points, selections.
  persist,

  /// `LocalPermanentData`: device-level flags.
  permanent,
}

class SaveDocument {
  SaveDocument(this.kind, this.data, this.modifiedAt);
  final SaveDocumentKind kind;
  final Map<String, Object?> data;
  final DateTime? modifiedAt;
}

/// One account's documents as found on a device or in files.
class GameSave {
  GameSave({
    required this.profileId,
    required this.name,
    required this.release,
    required this.source,
  });

  /// The in-game player ID (`_profileId`).
  final String profileId;
  final String? name;
  final GameRelease? release;

  /// Where the files were read from, for display.
  final String source;
  final Map<SaveDocumentKind, SaveDocument> documents = {};

  Map<String, Object?> get player =>
      (documents[SaveDocumentKind.cache]?.data['_player']
          as Map<String, Object?>?) ??
      {};
  DateTime? get modifiedAt => documents[SaveDocumentKind.cache]?.modifiedAt;
}

/// A file offered to the collector.
class SaveCandidate {
  SaveCandidate({
    required this.bytes,
    required this.source,
    this.modifiedAt,
    this.release,
    this.group,
  });
  final Uint8List bytes;
  final String source;
  final DateTime? modifiedAt;
  final GameRelease? release;

  /// Files from the same account directory share a group, which is how the
  /// persist and permanent documents find their player.
  final String? group;
}

/// Turns candidate files into saves, whatever they came from. Names are
/// content hashes that change between versions, so a file is a save exactly
/// when it decrypts; the newest copy of an account wins.
class SaveCollector {
  final Map<String, GameSave> _byProfile = {};
  final Map<String, List<SaveDocument>> _orphans = {};
  final Map<String, String> _profileOfGroup = {};
  int unreadable = 0;

  /// Returns true when the file was a save document.
  bool offer(SaveCandidate candidate) {
    final data = SaveCodec.decode(candidate.bytes);
    if (data == null) return false;
    final kind = _kindOf(data);
    if (kind == null) {
      unreadable++;
      return false;
    }
    final document = SaveDocument(kind, data, candidate.modifiedAt);
    final group = candidate.group ?? candidate.source;
    if (kind != SaveDocumentKind.cache) {
      final profile = _profileOfGroup[group];
      if (profile != null) {
        _place(_byProfile[profile]!, document);
      } else {
        (_orphans[group] ??= []).add(document);
      }
      return true;
    }
    final player = data['_player'];
    final id = player is Map<String, Object?>
        ? _profileId(player['_profileId'])
        : null;
    if (id == null) {
      unreadable++;
      return false;
    }
    final identity = '${candidate.release?.server ?? "unknown"}:$id';
    final existing = _byProfile[identity];
    final newer =
        existing == null ||
        (candidate.modifiedAt != null &&
            (existing.modifiedAt == null ||
                candidate.modifiedAt!.isAfter(existing.modifiedAt!)));
    if (newer) {
      final name = (player as Map<String, Object?>)['_name'];
      _byProfile[identity] =
          GameSave(
              profileId: id,
              name: name is String && name.trim().isNotEmpty ? name : null,
              release: candidate.release ?? existing?.release,
              source: candidate.source,
            )
            ..documents.addAll(existing?.documents ?? const {})
            ..documents[SaveDocumentKind.cache] = document;
    }
    _profileOfGroup[group] = identity;
    for (final orphan in _orphans.remove(group) ?? const <SaveDocument>[]) {
      _place(_byProfile[identity]!, orphan);
    }
    return true;
  }

  List<GameSave> get saves => _byProfile.values.toList();

  static void _place(GameSave save, SaveDocument document) {
    final current = save.documents[document.kind];
    if (current == null ||
        (document.modifiedAt != null &&
            (current.modifiedAt == null ||
                document.modifiedAt!.isAfter(current.modifiedAt!)))) {
      save.documents[document.kind] = document;
    }
  }

  static SaveDocumentKind? _kindOf(Map<String, Object?> data) {
    if (data.containsKey('_player')) return SaveDocumentKind.cache;
    if (data.containsKey('_tutorialPhase') ||
        data.containsKey('_latestLiveResult') ||
        data.containsKey('_advResumePoints')) {
      return SaveDocumentKind.persist;
    }
    if (data.containsKey('_isTutorialCompleted') ||
        data.containsKey('_bulkDownloadLastCompletedAtTicks')) {
      return SaveDocumentKind.permanent;
    }
    return null;
  }

  static final _decimal = RegExp(r'^[1-9][0-9]{0,18}$');
  static String? _profileId(Object? raw) {
    final text = raw is int
        ? '$raw'
        : raw is String
        ? raw.trim()
        : null;
    if (text == null || !_decimal.hasMatch(text)) return null;
    if (text.length == 19 && text.compareTo('9223372036854775807') > 0) {
      return null;
    }
    return text;
  }
}
