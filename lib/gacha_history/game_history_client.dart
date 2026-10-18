import 'package:game_data_exporter/gacha_history.dart' show SavedGameSession;

import '../save/game_save.dart';

export 'package:game_data_exporter/gacha_history.dart'
    show
        GameHistoryClient,
        GameHistoryException,
        GameHistoryRegion,
        SavedGameSession;

SavedGameSession? historySessionFromSave(GameSave save) =>
    SavedGameSession.fromPersist(
      save.documents[SaveDocumentKind.persist]?.data,
    );
