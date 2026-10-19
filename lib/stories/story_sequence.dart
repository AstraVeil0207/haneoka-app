import 'package:flutter/foundation.dart';

import '../rendering/native_story_preferences.dart';

/// Optional app navigation actions, separate from the story command clock.
abstract interface class StorySequenceHost implements Listenable {
  bool get continuous;
  bool get available;
  Future<void> toggleContinuous();
  Future<void> complete({
    required String storyId,
    required int epoch,
    required int completionRevision,
    required bool automatic,
    required bool Function() isCurrent,
  });
  Future<void> interrupt();
}

String storyEpisodeGroup(Map episode) => episode['isAnotherEpisode'] == true
    ? 'perspectiveStory'
    : episode['isExtraEpisode'] == true
    ? 'extraStory'
    : 'bandStory';

/// Uses the chapter's declared episode order, as the web player's sequence does.
/// A partial chapter cannot silently skip an unavailable episode.
final class StorySequenceCatalog {
  StorySequenceCatalog(Map document)
    : episodes = {
        for (final entry in (document['episodes'] as Map? ?? const {}).entries)
          if (entry.value is Map) '${entry.key}': entry.value as Map,
      },
      chapters = [
        for (final chapter in (document['chapters'] as Map? ?? const {}).values)
          if (chapter is Map) chapter,
      ];

  final Map<String, Map> episodes;
  final List<Map> chapters;
  final _sequences = <String, List<String>?>{};

  List<String>? sequence(String storyId) =>
      _sequences.putIfAbsent(storyId, () => _sequence(storyId));

  List<String>? _sequence(String storyId) {
    final current = episodes[storyId];
    if (current == null || current['chapterId'] == null) return null;
    final chapterId = '${current['chapterId']}';
    final chapter = chapters
        .where((row) => '${row['chapterId']}' == chapterId)
        .firstOrNull;
    final declared = chapter?['episodes'];
    if (declared is! List || declared.isEmpty) return null;
    final ids = declared.map((id) => '$id').toList();
    if (ids.any((id) => !episodes.containsKey(id))) return null;
    final birthday = current['storyCategory'] == 'birthday';
    final group = storyEpisodeGroup(current);
    final result = [
      for (final id in ids)
        if ('${episodes[id]!['chapterId']}' == chapterId &&
            storyEpisodeGroup(episodes[id]!) == group &&
            (episodes[id]!['storyCategory'] == 'birthday') == birthday)
          id,
    ];
    return result.contains(storyId) ? List.unmodifiable(result) : null;
  }
}

/// Owns chapter selection and cancellation. The app host owns its route and
/// supplies the catalogue; the player reports a completed presentation epoch.
final class StorySequenceController extends ChangeNotifier
    implements StorySequenceHost {
  StorySequenceController({
    required this.currentId,
    required Future<Map> Function() loadCatalog,
    required this.onInterrupt,
    this.startAutomatically = false,
    this.automatic = false,
  }) {
    _ready = _prepare(loadCatalog);
  }

  String currentId;
  bool startAutomatically, automatic;
  final Future<void> Function() onInterrupt;
  late final Future<void> _ready;
  NativeStoryPreferences? _preferences;
  StorySequenceCatalog? _catalog;
  Object? preparationError;
  int _revision = 0;
  bool _closed = false;
  final _completed = <(int, int, int)>{};

  Map? get current => _catalog?.episodes[currentId];
  @override
  bool get available => _catalog?.sequence(currentId) != null;
  @override
  bool get continuous => available && (_preferences?.continuous ?? false);

  Future<void> _prepare(Future<Map> Function() loadCatalog) async {
    try {
      final (preferences, document) = await (
        NativeStoryPreferences.load(),
        loadCatalog(),
      ).wait;
      if (_closed) return;
      _preferences = preferences;
      _catalog = StorySequenceCatalog(document);
    } catch (error) {
      if (_closed) return;
      preparationError = error;
    }
    if (!_closed) notifyListeners();
  }

  @override
  Future<void> toggleContinuous() async {
    await _ready;
    if (_closed || !available || _preferences == null) return;
    await _preferences!.setContinuous(!_preferences!.continuous);
    if (!_closed) notifyListeners();
  }

  @override
  Future<void> complete({
    required String storyId,
    required int epoch,
    required int completionRevision,
    required bool automatic,
    required bool Function() isCurrent,
  }) async {
    if (_closed || storyId != currentId || !isCurrent()) return;
    final revision = _revision;
    if (!_completed.add((revision, epoch, completionRevision))) return;
    await _ready;
    if (_closed ||
        revision != _revision ||
        storyId != currentId ||
        !isCurrent() ||
        !continuous) {
      return;
    }
    final sequence = _catalog!.sequence(storyId)!;
    final index = sequence.indexOf(storyId);
    if (index < 0 || index + 1 >= sequence.length) return;
    currentId = sequence[index + 1];
    startAutomatically = true;
    this.automatic = automatic;
    ++_revision;
    notifyListeners();
  }

  @override
  Future<void> interrupt() async {
    if (_closed) return;
    ++_revision;
    await onInterrupt();
  }

  @override
  void dispose() {
    _closed = true;
    ++_revision;
    super.dispose();
  }
}
