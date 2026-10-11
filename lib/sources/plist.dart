import 'dart:convert';
import 'dart:typed_data';

/// Reads Apple property lists, binary (`bplist00`) or XML, into Dart values:
/// maps, lists, strings, ints, doubles, bools, DateTimes, Uint8Lists and
/// [PlistUid] references. Enough for an iOS backup's manifests.
Object? parsePlist(Uint8List bytes) {
  if (bytes.length > 8 &&
      ascii.decode(bytes.sublist(0, 8), allowInvalid: true) == 'bplist00') {
    return _BinaryPlist(bytes).root();
  }
  return _XmlPlist(utf8.decode(bytes, allowMalformed: true)).root();
}

/// A reference inside an NSKeyedArchiver object table.
class PlistUid {
  PlistUid(this.index);
  final int index;
}

class _BinaryPlist {
  _BinaryPlist(this.data) : view = ByteData.sublistView(data);
  final Uint8List data;
  final ByteData view;
  late final int _offsetSize, _refSize, _count, _top, _tableOffset;

  Object? root() {
    final trailer = data.length - 32;
    _offsetSize = data[trailer + 6];
    _refSize = data[trailer + 7];
    _count = _uint(trailer + 8, 8);
    _top = _uint(trailer + 16, 8);
    _tableOffset = _uint(trailer + 24, 8);
    return _object(_top, 0);
  }

  int _uint(int at, int size) {
    var value = 0;
    for (var i = 0; i < size; i++) {
      value = (value << 8) | data[at + i];
    }
    return value;
  }

  int _offsetOf(int ref) {
    if (ref >= _count) {
      throw const FormatException('plist reference out of range');
    }
    return _uint(_tableOffset + ref * _offsetSize, _offsetSize);
  }

  Object? _object(int ref, int depth) {
    if (depth > 64) throw const FormatException('plist nested too deeply');
    final at = _offsetOf(ref);
    final marker = data[at];
    final type = marker >> 4, info = marker & 0xf;
    (int, int) length() {
      if (info != 0xf) return (info, at + 1);
      final size = 1 << (data[at + 1] & 0xf);
      return (_uint(at + 2, size), at + 2 + size);
    }

    switch (type) {
      case 0x0:
        return info == 0x8
            ? false
            : info == 0x9
            ? true
            : null;
      case 0x1:
        final size = 1 << info;
        return size == 8 ? view.getInt64(at + 1) : _uint(at + 1, size);
      case 0x2:
        return info == 2 ? view.getFloat32(at + 1) : view.getFloat64(at + 1);
      case 0x3:
        return DateTime.utc(
          2001,
        ).add(Duration(microseconds: (view.getFloat64(at + 1) * 1e6).round()));
      case 0x4:
        final (n, start) = length();
        return Uint8List.sublistView(data, start, start + n);
      case 0x5:
        final (n, start) = length();
        return latin1.decode(data.sublist(start, start + n));
      case 0x6:
        final (n, start) = length();
        final units = [
          for (var i = 0; i < n; i++) view.getUint16(start + i * 2),
        ];
        return String.fromCharCodes(units);
      case 0x8:
        return PlistUid(_uint(at + 1, info + 1));
      case 0xa:
        final (n, start) = length();
        return [
          for (var i = 0; i < n; i++)
            _object(_uint(start + i * _refSize, _refSize), depth + 1),
        ];
      case 0xd:
        final (n, start) = length();
        return {
          for (var i = 0; i < n; i++)
            '${_object(_uint(start + i * _refSize, _refSize), depth + 1)}':
                _object(_uint(start + (n + i) * _refSize, _refSize), depth + 1),
        };
    }
    throw FormatException(
      'unsupported plist object 0x${marker.toRadixString(16)}',
    );
  }
}

class _XmlPlist {
  _XmlPlist(this.text);
  final String text;
  int _at = 0;

  Object? root() {
    _at = text.indexOf('<plist');
    _at = text.indexOf('>', _at) + 1;
    return _value();
  }

  String _tag() {
    _at = text.indexOf('<', _at);
    final end = text.indexOf('>', _at);
    final tag = text.substring(_at + 1, end).trim();
    _at = end + 1;
    return tag;
  }

  String _until(String close) {
    final end = text.indexOf(close, _at);
    final value = text.substring(_at, end);
    _at = end + close.length;
    return value;
  }

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  Object? _value() {
    final tag = _tag();
    switch (tag) {
      case 'dict':
        final map = <String, Object?>{};
        while (true) {
          final save = _at;
          final next = _tag();
          if (next == '/dict') break;
          if (next != 'key') {
            _at = save;
            throw const FormatException('plist dict without key');
          }
          final key = _unescape(_until('</key>'));
          map[key] = _value();
        }
        return map;
      case 'dict/':
        return <String, Object?>{};
      case 'array':
        final list = <Object?>[];
        while (true) {
          final save = _at;
          if (_tag() == '/array') break;
          _at = save;
          list.add(_value());
        }
        return list;
      case 'array/':
        return <Object?>[];
      case 'string':
        return _unescape(_until('</string>'));
      case 'string/':
        return '';
      case 'integer':
        return int.parse(_until('</integer>').trim());
      case 'real':
        return double.parse(_until('</real>').trim());
      case 'true/':
        return true;
      case 'false/':
        return false;
      case 'date':
        return DateTime.parse(_until('</date>').trim());
      case 'data':
        return base64.decode(_until('</data>').replaceAll(RegExp(r'\s'), ''));
    }
    throw FormatException('unsupported plist element <$tag>');
  }
}
