import 'package:vega_plugin_haneoka/render_profile.dart';

import 'native_story_sdf.dart';
import 'native_story_ui_source.dart';

/// Reuses the story font/material resource bridge for source phone TMP nodes.
final class NativeStoryChatText {
  NativeStoryChatText(
    this.ui,
    this.locale,
    this.textScale, {
    required this.uiLanguageMode,
  }) : fonts = ui.fontBank(locale, chat: true);
  final NativeStoryUiSource ui;
  final String locale;
  final double textScale;
  final int uiLanguageMode;
  final StoryFontBank fonts;
  late final _fontBankSignature = fonts.fonts
      .map((font) => '${font.id}:${font.sourceHash}')
      .join('|');
  final _materials = <String, StorySdfMaterialData>{};
  final _glyphs = <Object, StoryGlyphLayout>{};

  StorySdfMaterialData _material(
    StoryChatTextRequest request,
    StoryFontData font,
  ) {
    final authored = storyChatTextData(request.component).materialName;
    final exact = '${font.id}:$authored';
    final key = ui.materials.containsKey(exact) ? exact : '${font.id}-default';
    return _materials.putIfAbsent(key, () {
      final raw = ui.materials[key];
      if (raw is! Map) throw FormatException('story_chat_font_material:$key');
      return StorySdfMaterialData.fromRaw(
        Map<String, Object?>.from(raw),
        actualFont: font,
        sourceMaterialKey: key,
        sourcePath: '${NativeStoryUiSource.base}fonts/materials.json',
        sourceHash: ui.sourceHashes['fonts/materials.json']!,
      );
    });
  }

  StoryGlyphLayout measure(StoryChatTextRequest request) {
    final localizeEnabled =
        request.localizeComponent?['_localizeEnabled'] == 1 ||
        request.localizeComponent?['_localizeEnabled'] == true;
    final key = (
      request.key,
      request.sourceHash,
      request.text,
      request.width,
      request.height,
      locale,
      uiLanguageMode,
      _fontBankSignature,
      localizeEnabled,
    );
    if (_glyphs.length > 256) _glyphs.clear();
    return _glyphs.putIfAbsent(
      key,
      () => compileMeasuredStoryUiText(
        source: request.text,
        textData: storyChatTextData(request.component),
        binding: StoryTextSourceBinding.fromRaw(
          sourceHash: request.sourceHash,
          component: request.component,
          localizeComponent: request.localizeComponent,
        ),
        fonts: fonts,
        width: request.width,
        height: request.height,
        lineBreakRules: ui.lineBreakRules,
        fontScale: textScale,
        uiLanguageMode: uiLanguageMode,
        paddingResolver: (font, bold) => nativeStorySdfGlyphPadding(
          _material(request, font),
          font,
          bold: bold,
          extraPadding:
              request.component['m_enableExtraPadding'] == true ||
              request.component['m_enableExtraPadding'] == 1,
        ),
      ),
    );
  }

  StoryChatTextBatch emit(
    StoryChatTextRequest request,
    StoryGlyphLayout glyphs,
    StoryUiRect rect,
    double canvasWidth,
    double canvasHeight,
    double screenScale,
  ) {
    final meshes = <String, ProjectedMesh>{},
        materials = <String, NativeMaterial>{};
    final textures = <String, Uri>{}, draws = <NativeDraw>[];
    final visible = glyphs.visibleQuads(request.visibleCharacters).toList();
    var start = 0, batch = 0;
    final textData = storyChatTextData(request.component);
    final binding = StoryTextSourceBinding.fromRaw(
      sourceHash: request.sourceHash,
      component: request.component,
      localizeComponent: request.localizeComponent,
    );
    final margin = request.component['m_margin'] as Map;
    final innerHeight =
        rect.height -
        (margin['y'] as num).toDouble() -
        (margin['w'] as num).toDouble();
    final offset = switch (textData.vertical) {
      256 => 0.0,
      512 => (innerHeight - glyphs.height) / 2,
      1024 => innerHeight - glyphs.height,
      final value => throw UnsupportedError('story_chat_text_vertical:$value'),
    };
    while (start < visible.length) {
      final first = visible[start];
      var end = start + 1;
      while (end < visible.length &&
          visible[end].atlasAsset == first.atlasAsset &&
          visible[end].fontId == first.fontId &&
          visible[end].bold == first.bold &&
          visible[end].glyphScale == first.glyphScale) {
        end++;
      }
      final key = 'chat:${request.key}:glyph:${batch++}';
      final font = ui.fonts[first.fontId]!;
      final material = _material(request, font);
      meshes[key] = nativeStoryGlyphMesh(
        visible.sublist(start, end),
        originX: rect.x,
        originY: rect.y + offset + binding.marginTopFor(request.text),
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
      );
      materials[key] = NativeMaterial(
        texture: first.atlasAsset,
        recipe: NativeMaterialRecipe.sdfText,
        textureAlpha: NativeTextureAlpha.premultiplied,
        uniformFloats: nativeStorySdfUniforms(
          material,
          glyphScale: first.glyphScale!,
          screenScale: screenScale,
          bold: first.bold,
        ),
      );
      textures[first.atlasAsset] = Uri.parse(
        'haneoka-asset:${first.atlasAsset}',
      );
      draws.add(NativeDraw(mesh: key, material: key));
      start = end;
    }
    return StoryChatTextBatch(
      meshes: meshes,
      materials: materials,
      textures: textures,
      draws: draws,
    );
  }
}
