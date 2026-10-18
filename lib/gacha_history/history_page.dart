import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/haneoka_account.dart';
import '../core/api.dart';
import '../core/app_state.dart';
import '../core/storage.dart';
import '../save/account_store.dart';
import '../save/game_save.dart';
import '../shell/links.dart';
import '../sources/files.dart';
import '../ui/adb_sheet.dart';
import '../ui/import_screen.dart';
import '../ui/game_release_picker.dart';
import 'game_history_client.dart';
import 'history_catalog.dart';
import 'history_repository.dart';
import 'history_screen.dart';
import 'history_snapshot.dart';
import 'history_view.dart';

void openGameHistory(BuildContext context, GameSave save) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryPage(initialSave: save, readOnOpen: true),
        settings: const RouteSettings(name: '/gacha-history'),
      ),
    );

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.initialSave, this.readOnOpen = false});
  final GameSave? initialSave;
  final bool readOnOpen;
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryChoice {
  const _HistoryChoice(this.key, this.region, this.save, this.record);
  final String key;
  final GameHistoryRegion region;
  final GameSave? save;
  final StoredHistory? record;
}

class _HistoryPageState extends State<HistoryPage> {
  final _repository = HistoryRepository.instance;
  final _accounts = AccountStore.instance;
  static final _catalogs = <(HaneokaApi, int), Future<HistoryCatalog>>{};
  String _selected = '';
  String? _errorCode;
  bool _importing = false;
  bool _opened = false;
  GachaHistoryConversion? _conversion;

  String _t(String key) =>
      AppScope.of(context).text('catalog.gachaHistory.$key');

  @override
  void initState() {
    super.initState();
    _repository.addListener(_changed);
    _accounts.addListener(_changed);
    unawaited(_load());
  }

  Future<void> _load() async {
    await Future.wait([_repository.load(), _accounts.load()]);
    final preferences = await SharedPreferences.getInstance();
    final currency = preferences.getString('gachaHistory.currency');
    final price = preferences.getDouble('gachaHistory.unitGemPrice');
    if (currency != null &&
        const {
          'JPY',
          'TWD',
          'HKD',
          'MOP',
          'USD',
          'KRW',
          'CNY',
        }.contains(currency)) {
      _conversion = GachaHistoryConversion(
        currencyCode: currency,
        unitGemPrice: price != null && price.isFinite && price >= 0
            ? price
            : null,
      );
    }
    if (mounted) setState(() {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _repository.removeListener(_changed);
    _accounts.removeListener(_changed);
    super.dispose();
  }

  List<_HistoryChoice> _choices() {
    final saves = [..._accounts.saves];
    final initial = widget.initialSave;
    if (initial != null &&
        !saves.any((save) => historySaveKey(save) == historySaveKey(initial))) {
      saves.insert(0, initial);
    }
    final records = {
      for (final record in _repository.records) record.key: record,
    };
    final choices = [
      for (final save in saves)
        for (final region in GameHistoryRegion.values)
          if (region.catalogServer == save.release?.server)
            _HistoryChoice(
              HistoryRepository.accountKey(save, region),
              region,
              save,
              records[HistoryRepository.accountKey(save, region)],
            ),
    ];
    final used = choices.map((choice) => choice.key).toSet();
    return [
      ...choices,
      for (final record in records.values)
        if (!used.contains(record.key))
          _HistoryChoice(
            record.key,
            GameHistoryRegion.values.firstWhere(
              (region) => region.id == record.snapshot.server,
            ),
            null,
            record,
          ),
    ];
  }

  String _regionLabel(GameHistoryRegion region) => _t(switch (region) {
    GameHistoryRegion.jp => 'regionJp',
    GameHistoryRegion.hmt => 'regionHmt',
    GameHistoryRegion.en => 'regionEn',
    GameHistoryRegion.ko => 'regionKo',
  });

  String? get _error => _errorCode == null
      ? null
      : _t(switch (_errorCode) {
          'history_missing_session' => 'errorMissingSession',
          'history_session_expired' => 'errorSessionExpired',
          'history_service_unavailable' => 'errorServiceUnavailable',
          'history_version_unavailable' => 'errorVersionUnavailable',
          'history_response_invalid' => 'errorResponseInvalid',
          'history_import_invalid' => 'errorImportInvalid',
          'history_catalog_unavailable' => 'errorCatalogUnavailable',
          _ => 'errorNetwork',
        });

  Future<void> _refresh(String key) async {
    final choice = _choices().where((value) => value.key == key).firstOrNull;
    if (choice?.save == null) return;
    setState(() {
      _selected = key;
      _errorCode = null;
    });
    try {
      await _repository.refresh(choice!.save!, choice.region);
    } on GameHistoryException catch (error) {
      if (mounted) setState(() => _errorCode = error.code);
    } on Exception {
      if (mounted) setState(() => _errorCode = 'history_network_error');
    }
  }

  Future<void> _acceptSaves(Iterable<GameSave> values) async {
    final saves = values.toList();
    if (saves.isEmpty || saves.any((save) => save.release == null)) {
      throw const FormatException('history_import_invalid');
    }
    for (final save in saves) {
      await _accounts.put(save);
      unawaited(HaneokaAccount.instance.syncIfLinked(save));
    }
    final save = saves.first;
    final region = save.release == GameRelease.jp
        ? GameHistoryRegion.jp
        : GameHistoryRegion.hmt;
    if (!mounted) return;
    setState(() => _selected = HistoryRepository.accountKey(save, region));
    if (SavedGameSession.fromSave(save) != null &&
        (save.release == GameRelease.jp ||
            save.release == GameRelease.intlOfficial)) {
      unawaited(_refresh(_selected));
    }
  }

  Future<void> _files() async {
    final chosen = await FilePicker.pickFiles();
    if (chosen.isEmpty || !mounted) return;
    setState(() {
      _importing = true;
      _errorCode = null;
    });
    CacheStorage.instance.beginImport();
    try {
      final collector = SaveCollector();
      final initialRelease =
          _choices()
              .where((value) => value.key == _selected)
              .firstOrNull
              ?.save
              ?.release ??
          (AppScope.of(context).server == 'jp'
              ? GameRelease.jp
              : GameRelease.intlOfficial);
      GameRelease? rawRelease;
      var snapshots = 0;
      final rawAccounts = <GameSave>[];
      var totalBytes = 0;
      for (final file in chosen) {
        final length = await file.length();
        if (length == null) {
          throw const FormatException('history_import_invalid');
        }
        totalBytes += length;
        if (length > historyResponseLimit * 2 ||
            totalBytes > historyResponseLimit * 4) {
          throw const FormatException('history_import_invalid');
        }
        final bytes = await file.readAsBytes();
        Object? json;
        try {
          json = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          json = null;
        }
        if (json is Map &&
            (json['schema'] == historySnapshotSchema ||
                json['format'] == 'otonote-gacha-history')) {
          final record = await _repository.import(
            HistorySnapshot.fromJson(json),
          );
          _selected = record.key;
          snapshots++;
        } else if (AccountStore.decode(json) case final save?) {
          if (save.release == null) {
            throw const FormatException('history_import_invalid');
          }
          rawAccounts.add(save);
        } else {
          if (!mounted) return;
          rawRelease ??= await chooseGameSaveRelease(
            context,
            initial: initialRelease,
          );
          if (rawRelease == null) return;
          FileSaveSource(
            collector,
            release: rawRelease,
          ).addBytes(bytes, file.path ?? file.name);
        }
      }
      if (collector.saves.isNotEmpty || rawAccounts.isNotEmpty) {
        await _acceptSaves([...collector.saves, ...rawAccounts]);
      } else if (snapshots == 0) {
        throw const FormatException('history_import_invalid');
      }
    } on TypeError {
      if (mounted) setState(() => _errorCode = 'history_import_invalid');
    } on Exception {
      if (mounted) setState(() => _errorCode = 'history_import_invalid');
    } finally {
      CacheStorage.instance.endImport();
      if (mounted) setState(() => _importing = false);
    }
  }

  void _source(GachaHistoryImportSource source) {
    switch (source) {
      case GachaHistoryImportSource.files:
        unawaited(_files());
      case GachaHistoryImportSource.saved:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AccountsScreen(onReadHistory: openGameHistory),
          ),
        );
      case GachaHistoryImportSource.adb:
        unawaited(
          showAdbSheet(
            context,
            onRead: (read) async {
              final collector = SaveCollector();
              await read(collector);
              await _acceptSaves(collector.saves);
            },
          ),
        );
    }
  }

  Future<void> _export(GachaHistoryExport selection) async {
    final choice = _choices()
        .where((value) => value.key == selection.accountKey)
        .firstOrNull;
    final snapshot = choice?.record?.snapshot;
    if (snapshot == null) return;
    final indexes = selection.batches
        .map((batch) => int.tryParse(batch.id.split(':').last))
        .whereType<int>()
        .toSet();
    final selected = snapshot.selected(indexes);
    await FilePicker.saveFile(
      fileName: 'haneoka-gacha-${snapshot.server}.json',
      bytes: Uint8List.fromList(utf8.encode(jsonEncode(selected.toJson()))),
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
  }

  Future<void> _images(List<GlobalKey> pages) async {
    final archive = Archive();
    Uint8List? first;
    for (var index = 0; index < pages.length; index++) {
      final boundary = pages[index].currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw const FormatException('history_image');
      }
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const FormatException('history_image');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        first ??= bytes;
        archive.addFile(
          ArchiveFile('haneoka-gacha-${index + 1}.png', bytes.length, bytes),
        );
      } finally {
        image.dispose();
      }
    }
    if (pages.isEmpty || first == null) return;
    final zipped = pages.length > 1;
    await FilePicker.saveFile(
      fileName: 'haneoka-gacha.${zipped ? 'zip' : 'png'}',
      bytes: zipped ? Uint8List.fromList(ZipEncoder().encode(archive)) : first,
      type: FileType.custom,
      allowedExtensions: [zipped ? 'zip' : 'png'],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final choices = _choices();
    if (_selected.isEmpty && choices.isNotEmpty) {
      final initial = widget.initialSave;
      _selected =
          choices
              .where(
                (value) =>
                    initial != null &&
                    value.save != null &&
                    historySaveKey(value.save!) == historySaveKey(initial),
              )
              .firstOrNull
              ?.key ??
          choices.first.key;
    }
    final current = choices
        .where((value) => value.key == _selected)
        .firstOrNull;
    if (!_opened && current != null) {
      _opened = true;
      if (widget.readOnOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_refresh(_selected));
        });
      }
    }
    final snapshot = current?.record?.snapshot;
    final api = state.apiFor(current?.region.catalogServer ?? state.server);
    final catalog = cachedResource(_catalogs, (
      api,
      api.revision,
    ), () => HistoryCatalog.load(api));
    return FutureBuilder<HistoryCatalog>(
      key: ValueKey((api, api.revision)),
      future: catalog,
      builder: (context, data) {
        final source = data.data;
        final fallback = snapshot == null
            ? <GachaHistoryBatch>[]
            : [
                for (final (index, execution) in snapshot.executions.indexed)
                  GachaHistoryBatch(
                    id: '$index',
                    accountKey: _selected,
                    poolId: execution.poolId ?? '',
                    pulledAt: execution.executedAt == null
                        ? null
                        : DateTime.fromMillisecondsSinceEpoch(
                            execution.executedAt! * 1000,
                            isUtc: true,
                          ),
                    drawCount: execution.prizes.length,
                    prizes: [
                      for (final prize in execution.prizes)
                        GachaHistoryPrize(
                          id: prize.prizeId,
                          kind: 'unknown',
                          name: '${_t('unknown')} · ${prize.prizeId}',
                          rarity: '',
                          rarityLabel: _t('unknown'),
                          quantity: 1,
                        ),
                    ],
                    cost: GachaHistoryCost(
                      freeGems: execution.freeGems,
                      paidGems: execution.paidGems,
                      tickets: execution.tickets,
                    ),
                  ),
              ];
        return GachaHistoryScreen(
          accounts: [
            for (final choice in choices)
              GachaHistoryAccount(
                key: choice.key,
                server: choice.region.id,
                serverLabel: _regionLabel(choice.region),
                label:
                    choice.save?.name ??
                    choice.record?.snapshot.queriedAt
                        .toLocal()
                        .toIso8601String() ??
                    _t('account'),
              ),
          ],
          pools:
              source?.poolViews(
                state.text.text,
                (category) => state.text(
                  'catalog.recruitments.types.$category',
                  category,
                ),
              ) ??
              const [],
          batches: snapshot == null
              ? const []
              : source?.batchViews(
                      snapshot,
                      _selected,
                      state.text.text,
                      _t('unknown'),
                    ) ??
                    fallback,
          selectedAccountKey: _selected,
          historyLoaded: snapshot != null,
          busy: _importing || _repository.isReading(_selected),
          error: _error,
          catalogLoading: data.connectionState == ConnectionState.waiting,
          catalogError: data.hasError ? _t('errorCatalogUnavailable') : null,
          onCatalogRetry: () => setState(() {
            _catalogs.remove((api, api.revision));
          }),
          onAccountChanged: (key) => setState(() {
            _selected = key;
            _errorCode = null;
          }),
          onRefresh: current?.save == null
              ? null
              : (key) => unawaited(_refresh(key)),
          onImportSource: _source,
          availableImportSources: [
            GachaHistoryImportSource.saved,
            GachaHistoryImportSource.files,
            if (!Platform.isAndroid && !Platform.isIOS)
              GachaHistoryImportSource.adb,
          ],
          onExport: snapshot == null
              ? null
              : (value) => unawaited(_export(value)),
          onExportImage: snapshot == null ? null : _images,
          currencyConversion:
              _conversion ??
              GachaHistoryConversion(
                currencyCode: switch (current?.region) {
                  GameHistoryRegion.jp => 'JPY',
                  GameHistoryRegion.en => 'USD',
                  GameHistoryRegion.ko => 'KRW',
                  _ => 'TWD',
                },
                unitGemPrice: null,
              ),
          onConversionChanged: (value) {
            setState(() => _conversion = value);
            unawaited(_saveConversion(value));
          },
          onOpenCard: (href) => unawaited(openLink(context, href)),
        );
      },
    );
  }

  Future<void> _saveConversion(GachaHistoryConversion value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('gachaHistory.currency', value.currencyCode);
    if (value.unitGemPrice case final price?) {
      await preferences.setDouble('gachaHistory.unitGemPrice', price);
    } else {
      await preferences.remove('gachaHistory.unitGemPrice');
    }
  }
}
