import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart' as media;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage.dart';

class NativeChartAudio {
  NativeChartAudio(
    this.ref,
    this.file,
    this.waveFile,
    this.waveform,
    this.minimum,
    this.maximum,
    this.candidates,
  );
  final ChartAudioRef ref;
  final File file, waveFile;
  final Float32List waveform, minimum, maximum;
  int _leases = 0;
  bool _retired = false;
  Future<void> Function() retain() {
    if (_retired) throw StateError('audio_closed');
    _leases++;
    var released = false;
    return () async {
      if (released) return;
      released = true;
      _leases--;
      if (_retired && _leases == 0 && await waveFile.exists()) {
        await waveFile.delete();
      }
    };
  }

  Future<void> close() async {
    _retired = true;
    if (_leases == 0 && await waveFile.exists()) await waveFile.delete();
  }

  final List<(double, double)> candidates;
}

Future<NativeChartAudio> decodeChartAudio(
  ChartCreationStore store,
  File file, {
  String? name,
  String? type,
}) async {
  final size = await file.length();
  if (size == 0 || size > 64 * 1024 * 1024) {
    throw const FormatException('audio_size');
  }
  final wave = await normalizeChartAudio(file);
  try {
    final analysis = await Isolate.run(() => _analyzeWave(wave.path));
    final duration = analysis.duration;
    final candidates = await Isolate.run(
      () => _tempoCandidates(analysis.rms, duration),
    );
    final ref = await store.importAudio(
      file,
      name: name ?? p.basename(file.path),
      type: type ?? chartAudioType(name ?? file.path),
      duration: duration,
    );
    return NativeChartAudio(
      ref,
      store.audioFile(ref),
      wave,
      analysis.rms,
      analysis.minimum,
      analysis.maximum,
      candidates,
    );
  } catch (_) {
    await wave.delete();
    rethrow;
  }
}

/// The existing native MPV decoder renders into a PCM file without an audio device.
/// All imports and Sonolus uploads share stereo 22050 Hz signed 16-bit WAV.
Future<File> normalizeChartAudio(File input) async {
  media.MediaKit.ensureInitialized();
  final root = await getTemporaryDirectory();
  final output = File(
    p.join(
      root.path,
      'haneoka-chart-pcm-${DateTime.now().microsecondsSinceEpoch}.wav',
    ),
  );
  final player = media.Player(
    configuration: const media.PlayerConfiguration(
      vo: 'null',
      bufferSize: 1024 * 1024,
    ),
  );
  final completed = Completer<void>();
  final subscriptions = <StreamSubscription>[
    player.stream.completed.listen((value) {
      if (value && !completed.isCompleted) completed.complete();
    }),
    player.stream.error.listen((value) {
      if (!completed.isCompleted) {
        completed.completeError(const FormatException('audio_decode'));
      }
    }),
    player.stream.duration.listen((value) {
      if (value.inMicroseconds > 600000000 && !completed.isCompleted) {
        completed.completeError(const FormatException('audio_duration'));
      }
    }),
  ];
  // Subscribe before opening: short files can finish inside the open request.
  unawaited(completed.future.catchError((Object _) {}));
  var succeeded = false;
  try {
    final backend = player.platform as media.NativePlayer;
    for (final entry in <String, String>{
      'ao': 'pcm',
      'ao-pcm-file': output.path,
      'ao-pcm-waveheader': 'yes',
      'ao-pcm-append': 'no',
      'audio-samplerate': '22050',
      'audio-channels': 'stereo',
      'audio-format': 's16',
      'untimed': 'yes',
      'vid': 'no',
      'end': '601',
    }.entries) {
      await backend.setProperty(entry.key, entry.value);
    }
    await player.open(media.Media(input.uri.toString()), play: true);
    await completed.future.timeout(const Duration(seconds: 30));
    succeeded = true;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await player.dispose();
    if (!succeeded && await output.exists()) await output.delete();
  }
  if (!await output.exists()) throw const FormatException('audio_decode');
  return output;
}

typedef _WaveAnalysis = ({
  double duration,
  Float32List rms,
  Float32List minimum,
  Float32List maximum,
});
_WaveAnalysis _analyzeWave(String path) {
  final bytes = File(path).readAsBytesSync(),
      view = ByteData.sublistView(bytes);
  if (bytes.length < 44 ||
      String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('audio_decode');
  }
  int? channels, rate, bits, format, dataStart, dataSize;
  for (var at = 12; at + 8 <= bytes.length;) {
    final name = String.fromCharCodes(bytes.sublist(at, at + 4)),
        length = view.getUint32(at + 4, Endian.little),
        begin = at + 8;
    if (length > bytes.length - begin) {
      throw const FormatException('audio_decode');
    }
    if (name == 'fmt ' && length >= 16) {
      format = view.getUint16(begin, Endian.little);
      channels = view.getUint16(begin + 2, Endian.little);
      rate = view.getUint32(begin + 4, Endian.little);
      bits = view.getUint16(begin + 14, Endian.little);
      if (format == 0xfffe &&
          length >= 40 &&
          view.getUint32(begin + 24, Endian.little) == 1) {
        format = 1;
      }
    }
    if (name == 'data') {
      dataStart = begin;
      dataSize = length;
    }
    at = begin + length + (length & 1);
  }
  if (format != 1 ||
      channels != 2 ||
      rate != 22050 ||
      bits != 16 ||
      dataStart == null ||
      dataSize == null) {
    throw const FormatException('audio_decode');
  }
  final frames = dataSize ~/ 4, duration = frames / 22050;
  if (frames == 0 || duration > 600) {
    throw const FormatException('audio_duration');
  }
  if (dataStart != 44) {
    final header = Uint8List(44), out = ByteData.sublistView(header);
    header.setRange(0, 4, 'RIFF'.codeUnits);
    out.setUint32(4, 36 + dataSize, Endian.little);
    header.setRange(8, 12, 'WAVE'.codeUnits);
    header.setRange(12, 16, 'fmt '.codeUnits);
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little);
    out.setUint16(22, 2, Endian.little);
    out.setUint32(24, 22050, Endian.little);
    out.setUint32(28, 88200, Endian.little);
    out.setUint16(32, 4, Endian.little);
    out.setUint16(34, 16, Endian.little);
    header.setRange(36, 40, 'data'.codeUnits);
    out.setUint32(40, dataSize, Endian.little);
    final output = File(path).openSync(mode: FileMode.write);
    try {
      output.writeFromSync(header);
      output.writeFromSync(bytes, dataStart, dataStart + dataSize);
      output.flushSync();
    } finally {
      output.closeSync();
    }
  }
  final count = math.max(1, (duration * 100).ceil()),
      rms = Float32List(count),
      minimum = Float32List(count),
      maximum = Float32List(count);
  for (var bin = 0; bin < count; bin++) {
    final start = math.min(frames, (bin * frames / count).floor()),
        end = math.min(
          frames,
          math.max(start + 1, ((bin + 1) * frames / count).floor()),
        );
    var low = double.infinity, high = -double.infinity, sum = 0.0;
    for (var frame = start; frame < end; frame++) {
      for (var channel = 0; channel < 2; channel++) {
        final sample =
            view.getInt16(dataStart + frame * 4 + channel * 2, Endian.little) /
            32768;
        low = math.min(low, sample);
        high = math.max(high, sample);
        sum += sample * sample;
      }
    }
    minimum[bin] = end > start ? low : 0;
    maximum[bin] = end > start ? high : 0;
    rms[bin] = end > start ? math.sqrt(sum / (end - start) / 2) : 0;
  }
  return (duration: duration, rms: rms, minimum: minimum, maximum: maximum);
}

List<(double, double)> _tempoCandidates(Float32List rms, double duration) {
  final length = math.min(rms.length, 9000), rate = rms.length / duration;
  final onset = Float32List(length);
  var energy = 0.0;
  for (var i = 1; i < length; i++) {
    onset[i] = math.max(0, rms[i] - rms[i - 1]);
    energy += onset[i] * onset[i];
  }
  if (energy <= 1e-6 || duration < 4) return [];
  final scores = <(int, double)>[];
  for (
    var lag = math.max(1, (rate * 60 / 240).floor());
    lag <= (rate * 60 / 50).ceil() && lag < length / 3;
    lag++
  ) {
    var cross = 0.0, a = 0.0, b = 0.0;
    for (var i = lag; i < length; i++) {
      cross += onset[i] * onset[i - lag];
      a += onset[i] * onset[i];
      b += onset[i - lag] * onset[i - lag];
    }
    final divisor = math.sqrt(a * b);
    scores.add((lag, cross / (divisor == 0 ? 1 : divisor)));
  }
  final peaks = [
    for (final (i, item) in scores.indexed)
      if (item.$2 >= .15 &&
          item.$2 >= (i == 0 ? 0 : scores[i - 1].$2) &&
          item.$2 >= (i + 1 == scores.length ? 0 : scores[i + 1].$2))
        item,
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return peaks
      .take(3)
      .map((v) => ((rate * 600 / v.$1).round() / 10, v.$2))
      .toList();
}

String chartAudioType(String name) => switch (p.extension(name).toLowerCase()) {
  '.mp3' => 'audio/mpeg',
  '.ogg' => 'audio/ogg',
  '.flac' => 'audio/flac',
  '.m4a' || '.aac' => 'audio/mp4',
  _ => 'audio/wav',
};

/// The editor's built-in audio is a real portable WAV with a 120 BPM click.
Future<File> chartExampleAudio() async {
  final root = await getTemporaryDirectory(),
      file = File(p.join(root.path, 'haneoka-chart-example.wav'));
  if (await file.exists()) return file;
  final bytes = await Isolate.run(() {
    const rate = 22050, frames = rate * 16;
    final bytes = Uint8List(44 + frames * 2),
        data = ByteData.sublistView(bytes);
    void text(int at, String value) {
      bytes.setRange(at, at + value.length, value.codeUnits);
    }

    text(0, 'RIFF');
    data.setUint32(4, bytes.length - 8, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    text(36, 'data');
    data.setUint32(40, frames * 2, Endian.little);
    for (var i = 0; i < frames; i++) {
      final t = (i % (rate ~/ 2)) / rate;
      final sound = t < .05
          ? math.sin(t * 2 * math.pi * 880) * math.exp(-t * 100) * .5
          : 0.0;
      data.setInt16(44 + i * 2, (sound * 32767).round(), Endian.little);
    }
    return bytes;
  });
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
