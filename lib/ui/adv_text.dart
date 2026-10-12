import 'dart:math' as math;

import 'package:flutter/material.dart';

/// TextMeshPro markup used by ADV scripts. Unclosed style tags stay active;
/// unknown tags are discarded while their text is retained.
class AdvText extends StatelessWidget {
  const AdvText(this.source, {super.key, this.style, this.nativeBase = 36});
  final String source;
  final TextStyle? style;
  final double nativeBase;

  static String plain(String source) => source
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(r'\n', '\n');

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final size = base.fontSize ?? 16;
    final spans = <InlineSpan>[];
    final frames = <(String, TextStyle)>[];
    TextStyle current() => frames.isEmpty ? base : frames.last.$2;
    final value = source
        .replaceAll(r'\n', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    var index = 0;
    while (index < value.length) {
      if (value[index] != '<') {
        final next = value.indexOf('<', index);
        final end = next < 0 ? value.length : next;
        spans.add(
          TextSpan(text: value.substring(index, end), style: current()),
        );
        index = end;
        continue;
      }
      final end = value.indexOf('>', index);
      if (end < 0) break;
      final token = value.substring(index + 1, end).trim();
      final closing = token.startsWith('/');
      final body = closing ? token.substring(1).trim() : token;
      final split = body.indexOf('=');
      final tag = (split < 0 ? body : body.substring(0, split))
          .trim()
          .toLowerCase();
      var arg = split < 0 ? '' : body.substring(split + 1).trim();
      if (arg.length >= 2 &&
          (arg.startsWith('"') && arg.endsWith('"') ||
              arg.startsWith("'") && arg.endsWith("'"))) {
        arg = arg.substring(1, arg.length - 1);
      }
      index = end + 1;
      if (closing) {
        final at = frames.lastIndexWhere((f) => f.$1 == tag);
        if (at >= 0) frames.removeRange(at, frames.length);
        continue;
      }
      if (tag == 'br' || tag == 'br/') {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }
      if (tag == 'noparse') {
        final until = value.toLowerCase().indexOf('</noparse>', index);
        spans.add(
          TextSpan(
            text: value.substring(index, until < 0 ? value.length : until),
            style: current(),
          ),
        );
        index = until < 0 ? value.length : until + 10;
        continue;
      }
      if (tag == 'r' || tag == 'ruby') {
        final close = RegExp(
          r'</(?:r|ruby)\s*>',
          caseSensitive: false,
        ).firstMatch(value.substring(index));
        final until = close == null ? value.length : index + close.start;
        final rubyBase = plain(value.substring(index, until));
        final textStyle = current();
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.bottom,
            child: Semantics(
              label: rubyBase,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    arg,
                    style: textStyle.copyWith(
                      fontSize: (textStyle.fontSize ?? size) * 0.5,
                      height: 1,
                    ),
                  ),
                  Text(rubyBase, style: textStyle.copyWith(height: 1.2)),
                ],
              ),
            ),
          ),
        );
        index = close == null ? value.length : index + close.end;
        continue;
      }
      final length = RegExp(r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+))(px|em|%)?$')
          .firstMatch(arg);
      final number = length == null ? null : double.tryParse(length[1]!);
      double scaledLength() => switch (length?[2]) {
        'em' => (number ?? 0) * (current().fontSize ?? size),
        '%' => (number ?? 0) / 100 * (current().fontSize ?? size),
        _ => (number ?? 0) * size / nativeBase,
      };
      if (tag == 'space' && number != null) {
        spans.add(
          WidgetSpan(
            child: SizedBox(width: math.max(0, scaledLength()), height: 0),
          ),
        );
        continue;
      }
      final previous = current();
      final next = switch (tag) {
        'b' => previous.copyWith(fontWeight: FontWeight.w700),
        'i' => previous.copyWith(fontStyle: FontStyle.italic),
        'u' => previous.copyWith(decoration: TextDecoration.underline),
        's' => previous.copyWith(decoration: TextDecoration.lineThrough),
        'color' when _color(arg) != null => previous.copyWith(
          color: _color(arg),
        ),
        'mark' when _color(arg) != null => previous.copyWith(
          backgroundColor: _color(arg),
        ),
        'cspace' when number != null => previous.copyWith(
          letterSpacing: scaledLength(),
        ),
        'size' when number != null => previous.copyWith(
          fontSize: math.max(
            0,
            length?[2] == '%'
                ? size * number / 100
                : length?[2] == 'em'
                ? size * number
                : arg.startsWith('+') || arg.startsWith('-')
                ? size * (nativeBase + number) / nativeBase
                : size * number / nativeBase,
          ),
        ),
        _ => null,
      };
      if (next != null) frames.add((tag, next));
    }
    return Text.rich(TextSpan(children: spans), style: base);
  }
}

Color? _color(String source) {
  final value = source.toLowerCase();
  const named = {
    'black': Colors.black,
    'white': Colors.white,
    'red': Color(0xFFFF0000),
    'green': Color(0xFF008000),
    'blue': Color(0xFF0000FF),
    'yellow': Color(0xFFFFFF00),
    'orange': Color(0xFFFFA500),
    'purple': Color(0xFF800080),
    'cyan': Color(0xFF00FFFF),
    'magenta': Color(0xFFFF00FF),
    'grey': Color(0xFF808080),
    'gray': Color(0xFF808080),
    'transparent': Colors.transparent,
  };
  if (named.containsKey(value)) return named[value];
  if (!RegExp(r'^#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$')
      .hasMatch(value)) {
    return null;
  }
  var hex = value.substring(1);
  if (hex.length <= 4) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex += 'ff';
  return Color(
    int.parse('${hex.substring(6)}${hex.substring(0, 6)}', radix: 16),
  );
}
