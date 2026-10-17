import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart';
import 'package:cassiopeia_plugin_our_notes/render_profile.dart';

import 'native_chart_document.dart';
import 'native_numeric_texture.dart';

typedef NativeChartIntroTextureBatch = ({
  Map<String, String> paths,
  Map<String, NativeTextureData> data,
});

/// Source packets, font metadata and decoded texels owned by one chart page.
final class NativeChartIntroResources {
  NativeChartIntroResources(this.fetch, this.resolve);
  final Future<Uint8List> Function(Uri) fetch;
  final Uri Function(String, NativeChartDocument) resolve;
  Future<Map<String, Object?>>? _packet;
  Future<SourceSdfFontBank>? _fonts;
  final _pixels = <(String, NativeTextureAlpha), NativeTextureData>{};
  bool _disposed = false;

  Future<Map<String, Object?>> _loadPacket() async => (jsonDecode(
    await loadHaneokaProfileString(
      '${haneokaProfileAssetRoot}intro-source.json',
    ),
  ) as Map).cast<String, Object?>();

  Future<SourceSdfFontBank> _loadFonts(Map<String, Object?> packet) async {
    final profile = await HaneokaProfileAssets.open();
    final fonts = <SourceFontData>[];
    for (final entry in (packet['fontMetadata'] as Map).entries) {
      final descriptor = entry.value as Map,
          path = descriptor['path'] as String,
          buffer = await loadHaneokaProfileAsset(path);
      final bytes = buffer.buffer.asUint8List(
        buffer.offsetInBytes,
        buffer.lengthInBytes,
      );
      final hash = sha256.convert(bytes).toString();
      if (hash != descriptor['sha256']) {
        throw FormatException('chart_intro_font_hash:${entry.key}');
      }
      fonts.add(
        SourceFontData.fromJson(
          (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>(),
          sourceHash: hash,
          coverageChannel: profile.fontCoverageChannel(
            (descriptor['atlases'] as List).cast<String>(),
          ),
          glyphPairs: descriptor['pairs'] as List?,
          actualAtlasAssetKeys: [
            for (
              var page = 0;
              page < (descriptor['atlases'] as List).length;
              page++
            )
              'intro:font:${entry.key}:$page',
          ],
        ),
      );
    }
    return SourceSdfFontBank(fonts);
  }

  Future<OurNotesIntroProjector?> create(
    NativeChartDocument selected,
    bool Function() current,
  ) async {
    final packet = await (_packet ??= _loadPacket());
    if (_disposed || !current()) return null;
    final profile = await HaneokaProfileAssets.open();
    profile.requireCapability('our-notes-chart-v1');
    if (packet['server'] != profile.packetSource['server'] ||
        packet['sourceId'] != profile.packetSource['sourceId']) {
      throw const FormatException('chart_intro_profile_provenance');
    }
    final fonts = await (_fonts ??= _loadFonts(packet));
    if (_disposed || !current()) return null;
    return OurNotesIntroProjector(
      packet,
      bandId: selected.bandId,
      fontBank: fonts,
      random: NativeAuthoredRandom(
        DateTime.now().microsecondsSinceEpoch & 0xffffffff,
      ),
    );
  }

  Future<NativeChartIntroTextureBatch> textures(
    OurNotesIntroProjector projector,
    NativeChartDocument selected,
    String locale,
    bool Function() current,
  ) async {
    final paths = projector.texturePaths(
      selected.source.server,
      canonicalSong: selected.canonicalSong,
      difficulty: selected.difficulty,
      locale: locale,
    );
    final groups = <NativeTextureAlpha, Map<String, String>>{
      NativeTextureAlpha.straight: projector.straightTexturePaths(
        selected.source.server,
      ),
      NativeTextureAlpha.independent: projector.independentTexturePaths(
        selected.source.server,
        canonicalSong: selected.canonicalSong,
        difficulty: selected.difficulty,
        locale: locale,
      ),
    };
    final result = <String, NativeTextureData>{};
    for (final group in groups.entries) {
      final uris = {
        for (final entry in group.value.entries)
          entry.key: resolve(entry.value, selected).toString(),
      };
      for (final uri in uris.values.toSet()) {
        if (_pixels.containsKey((uri, group.key))) continue;
        final numeric = await loadHaneokaProfileTexture(Uri.parse(uri));
        if (_disposed || !current()) {
          return (
            paths: <String, String>{},
            data: <String, NativeTextureData>{},
          );
        }
        if (numeric != null) _pixels[(uri, group.key)] = numeric;
      }
      final missing = uris.values
          .where((uri) => !_pixels.containsKey((uri, group.key)))
          .toSet()
          .toList();
      final encoded = await Future.wait([
        for (final uri in missing) fetch(Uri.parse(uri)),
      ]);
      if (_disposed || !current()) {
        return (
          paths: const <String, String>{},
          data: const <String, NativeTextureData>{},
        );
      }
      final decoded = await decodeNativeNumericTextures(
        Map.fromIterables(missing, encoded),
        alpha: group.key,
      );
      if (_disposed || !current()) {
        return (
          paths: const <String, String>{},
          data: const <String, NativeTextureData>{},
        );
      }
      for (final entry in decoded.entries) {
        _pixels[(entry.key, group.key)] = entry.value;
      }
      for (final entry in uris.entries) {
        result[entry.key] = _pixels[(entry.value, group.key)]!;
      }
    }
    return (paths: paths, data: result);
  }

  void releaseDecodedPixels() => _pixels.clear();

  void dispose() {
    _disposed = true;
    _pixels.clear();
    _packet = null;
    _fonts = null;
  }
}
