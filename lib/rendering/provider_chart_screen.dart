import 'dart:async';
import 'dart:convert';

import 'package:cassiopeia_plugin_our_notes/render_profile.dart';
import 'package:flutter/material.dart';

import '../chart/runtime_chart.dart';
import '../core/app_state.dart';
import '../core/provider_api.dart';
import '../core/resource_file_cache.dart';
import '../shell/page.dart';
import 'native_chart_document.dart';
import 'native_chart_player_screen.dart';
import 'sekai_chart.dart';

class ProviderChartScreen extends StatefulWidget {
  const ProviderChartScreen({
    super.key,
    required this.provider,
    required this.songId,
    this.difficulty = '3',
    this.region,
  });
  final String provider, songId, difficulty;
  final String? region;
  @override
  State<ProviderChartScreen> createState() => _ProviderChartScreenState();
}

class _ProviderChartScreenState extends State<ProviderChartScreen> {
  Future<NativeChartDocument>? _document;
  ProviderApi? _owned;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _document ??= _load();
  }

  Future<NativeChartDocument> _load() async {
    final state = AppScope.of(context),
        locale = state.text.locale,
        skinApi = state.api;
    final api = widget.region == null
        ? state.providerApi(widget.provider)
        : (_owned = ProviderApi(
            provider: widget.provider,
            locale: locale,
            region: widget.region,
          ));
    final song = (await api.catalog('songs', widget.songId) as Map)
            .cast<String, Object?>(),
        charts = (song['difficulty'] as List).cast<Map>();
    final index = int.tryParse(widget.difficulty),
        names = widget.provider == 'sekai'
            ? const ['easy', 'normal', 'hard', 'expert', 'master', 'append']
            : const ['easy', 'normal', 'hard', 'expert', 'special'];
    final difficulty = index == null
        ? widget.difficulty
        : names[index.clamp(0, names.length - 1)];
    final row = charts.firstWhere((r) => r['difficulty'] == difficulty);
    final score = api.asset('${row['file']}'),
        release = await skinApi.release();
    RuntimeChart? prepared;
    List<({double timeMs, double scale})> scales = const [];
    final offset = (song['bgmOffsetMs'] as num?)?.toDouble() ?? 0;
    if (widget.provider == 'sekai') {
      final lease = await resourceFileCache.acquire(
        score,
        kind: ResourceFileKind.renderResource,
      );
      try {
        final result = compileSekaiChart(utf8.decode(await lease.readBytes()));
        prepared = result.chart;
        scales = result.scales;
      } finally {
        await lease.release();
      }
    }
    return NativeChartDocument(
      source: RenderSource(
        server: skinApi.server,
        release: release,
        document:
            '${widget.provider}:${api.region}:${widget.songId}:$difficulty',
      ),
      sourceId: skinApi.sourceId,
      resourceBase: Uri.parse(skinApi.origin),
      scoreUri: score,
      musicUri: api.asset('${song['musicUrl']}'),
      jacketUri: api.asset('${song['jacketUrl']}'),
      bandId: (song['bandId'] as num?)?.toInt() ?? 1,
      title: state.songTitle(song['musicTitle']),
      difficulty: index ?? names.indexOf(difficulty),
      canonicalSong: {...song, 'musicTitle': song['musicTitle']},
      chart: prepared,
      audioOffsetMs: offset,
      timeScaleChanges: scales,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<NativeChartDocument>(
    future: _document,
    builder: (context, snapshot) {
      if (snapshot.data case final doc?) {
        return NativeChartPlayerScreen(
          document: doc,
          difficulty: doc.difficulty,
        );
      }
      final t = AppScope.of(context).text;
      return ShellPage(
        title: t('navigation.chart'),
        body: Center(
          child: snapshot.hasError
              ? FilledButton.tonal(
                  onPressed: () => setState(() => _document = _load()),
                  child: Text(t('common.actions.retry')),
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }
}
