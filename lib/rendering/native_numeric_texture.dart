import 'dart:isolate';
import 'dart:typed_data';

import 'package:haneoka_render_profile/core.dart';
import 'package:image/image.dart' as image;

/// Source FX texels preserve RGB even where alpha is zero. Decode off the UI
/// thread, then upload these numeric bytes through copyBufferToTexture.
NativeTextureData _decode(Uint8List png, NativeTextureAlpha alpha) {
  final decoded = image.decodePng(png);
  if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
    throw const FormatException('native_numeric_png');
  }
  return NativeTextureData(
    width: decoded.width,
    height: decoded.height,
    rgba: decoded.getBytes(order: image.ChannelOrder.rgba),
    alpha: alpha,
  );
}

Future<NativeTextureData> decodeNativeNumericTexture(Uint8List png) =>
    Isolate.run(() => _decode(png, NativeTextureAlpha.straight));

Future<Map<String, NativeTextureData>> decodeNativeNumericTextures(
  Map<String, Uint8List> pngs, {
  required NativeTextureAlpha alpha,
}) => Isolate.run(
  () => {
    for (final entry in pngs.entries) entry.key: _decode(entry.value, alpha),
  },
);
