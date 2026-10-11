/// A port of `@bbob/parser` 4.4.1 (lexer, parser and `TagNode`), which the
/// website uses for community markup. Positions are not tracked; everything
/// that shapes the tree follows the original, quirks included.
library;

const _open = '[';
const _close = ']';
const _quote = '"';
const _backslash = '\\';
const _slash = '/';
const _space = ' ';
const _tab = '\t';
const _eq = '=';
const _newLine = '\n';

/// A parsed tag: `[tag attr=value]content[/tag]`. Content holds strings and
/// tags.
class BBTag {
  BBTag(this.tag, this.attrs, this.content);
  final String tag;
  final Map<String, String> attrs;
  final List<Object> content;

  /// The node as the parser appends it: a new node sharing attrs and content.
  BBTag copy() => BBTag(tag, attrs, content);

  String toTagStart() => '$_open${_tagAttrs(tag, attrs)}$_close';
  String toTagEnd() => '$_open$_slash$tag$_close';
}

String _escapeAttrValue(String value) => value
    .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
    .replaceAllMapped(
      RegExp(r'(javascript|data|vbscript|file):', caseSensitive: false),
      (m) => '${m[1]}%3A',
    );

String _attrValue(String name, String value) =>
    '$name="${_escapeAttrValue(value)}"';

String _attrsToString(Map<String, String> values) => [
  '',
  for (final MapEntry(:key, :value) in values.entries) _attrValue(key, value),
].join(' ');

String? _uniqAttr(Map<String, String> attrs) {
  String? result;
  for (final key in attrs.keys) {
    result = attrs[key] == key ? attrs[key] : null;
  }
  return result;
}

String _tagAttrs(String tag, Map<String, String> params) {
  final uniq = _uniqAttr(params);
  if (uniq != null) {
    final attrs = Map.of(params)..remove(uniq);
    return '${_attrValue(tag, uniq)}${_attrsToString(attrs)}';
  }
  return '$tag${_attrsToString(params)}';
}

class _Chars {
  _Chars(this.s);
  final String s;
  int pos = 0;
  int get len => s.length;

  void skip([int n = 1]) => pos += n;
  bool hasNext() => len > pos;
  String getCurr() => pos < len ? s[pos] : '';
  String? getNext() => pos + 1 < len ? s[pos + 1] : null;
  String? getPrev() => pos - 1 >= 0 ? s[pos - 1] : null;
  bool isLast() => pos == len;
  bool includes(String value) => s.indexOf(value, pos) >= 0;

  String grabWhile(bool Function(String char) condition) {
    var start = 0;
    if (hasNext()) {
      start = pos;
      while (pos < len && condition(s[pos])) {
        pos++;
      }
    }
    return s.substring(start, pos);
  }

  String grabN(int n) => s.substring(pos, (pos + n).clamp(pos, len));

  String substrUntilChar(String char) {
    final index = s.indexOf(char, pos);
    return index >= 0 ? s.substring(pos, index) : '';
  }
}

enum _T { word, tag, attrName, attrValue, space, newLine }

class _Token {
  const _Token(this.type, this.value);
  final _T type;
  final String value;
  bool get isText => type == _T.space || type == _T.newLine || type == _T.word;
  bool get isTag => type == _T.tag;
  bool get isEnd => value.startsWith(_slash);
  @override
  String toString() => '$_open$value$_close';
}

String _trimChar(String value, String char) {
  var start = 0, end = value.length;
  while (start < end && value[start] == char) {
    start++;
  }
  while (end > start && value[end - 1] == char) {
    end--;
  }
  return value.substring(start, end);
}

String _unq(String value) =>
    _trimChar(value, _quote).replaceFirst('$_backslash$_quote', _quote);

bool _isWhiteSpace(String char) => char == _space || char == _tab;

class _Lexer {
  _Lexer(this.buffer, this.onToken, {required this.contextFreeTags});
  final String buffer;
  final void Function(_Token token) onToken;
  final List<String> contextFreeTags;
  final _nested = <String, bool>{};
  String _contextFree = '';
  late final _Chars chars = _Chars(buffer);

  static const _reserved = {
    _close,
    _open,
    _quote,
    _backslash,
    _space,
    _tab,
    _eq,
    _newLine,
    '!',
  };

  void _emit(_T type, String value) => onToken(_Token(type, value));

  bool isTokenNested(String value) {
    final end = '$_open$_slash$value$_close';
    return _nested[end] ??= buffer.contains(end);
  }

  void _setupContextFree(String name, [bool closing = false]) {
    if (_contextFree.isNotEmpty && closing) _contextFree = '';
    final lower = name.toLowerCase();
    if (_contextFree.isEmpty &&
        isTokenNested(name) &&
        contextFreeTags.contains(lower)) {
      _contextFree = lower;
    }
  }

  static const _word = 0, _tagState = 1, _attrsState = 2;
  static const _name = 0, _attr = 1, _value = 2;

  int _nextTagState(_Chars tag, int mode, bool singleValue) {
    if (mode == _attr) {
      final name = tag.grabWhile((c) => !(c == _eq || _isWhiteSpace(c)));
      final isEnd = tag.isLast();
      final isValue = tag.getCurr() != _eq;
      tag.skip();
      if (isEnd || isValue) {
        _emit(_T.attrValue, _unq(name));
      } else {
        _emit(_T.attrName, name);
      }
      if (isEnd) return _name;
      if (isValue) return _attr;
      return _value;
    }
    if (mode == _value) {
      var special = false;
      bool valid(String char) {
        final isQuote = char == _quote;
        final prev = tag.getPrev();
        final next = tag.getNext();
        final prevSlash = prev == _backslash;
        final nextEq = next == _eq;
        final isWs = _isWhiteSpace(char);
        final nextWs = next != null && _isWhiteSpace(next);
        if (special && (char == _eq || _isWhiteSpace(char))) return true;
        if (isQuote && !prevSlash) {
          special = !special;
          if (!special && !(nextEq || nextWs)) return false;
        }
        if (!singleValue) return !isWs;
        return true;
      }

      final name = tag.grabWhile(valid);
      tag.skip();
      _emit(_T.attrValue, _unq(name));
      if (tag.isLast()) return _name;
      return _attr;
    }
    final name = tag.grabWhile(
      (c) => !(c == _eq || _isWhiteSpace(c) || tag.isLast()),
    );
    _emit(_T.tag, name);
    _setupContextFree(name);
    tag.skip();
    if (singleValue) return _value;
    return tag.includes(_eq) ? _attr : _value;
  }

  int _stateTag() {
    final current = chars.getCurr();
    final next = chars.getNext();
    final nextReserved = next != null && _reserved.contains(next);
    chars.skip();
    final substr = chars.substrUntilChar(_close);
    final invalid = substr.isEmpty || substr.contains(_open);
    if (nextReserved || invalid || chars.isLast()) {
      _emit(_T.word, current);
      return _word;
    }
    final noAttrs = !substr.contains(_eq);
    final closing = substr[0] == _slash;
    if (noAttrs || closing) {
      final name = chars.grabWhile((c) => c != _close);
      chars.skip();
      _emit(_T.tag, name);
      _setupContextFree(name, closing);
      return _word;
    }
    return _attrsState;
  }

  int _stateAttrs() {
    final tagText = chars.grabWhile((c) => c != _close);
    final tag = _Chars(tagText);
    final tagName = tagText.split(_eq).first;
    final isEnd = tagName.startsWith(_slash);
    final singleValue = !isEnd && !tagName.contains(_space);
    var mode = _name;
    while (tag.hasNext()) {
      mode = _nextTagState(tag, mode, singleValue);
    }
    chars.skip();
    return _word;
  }

  int _stateWord() {
    final current = chars.getCurr();
    if (current == _newLine) {
      _emit(_T.newLine, current);
      chars.skip();
      return _word;
    }
    if (_isWhiteSpace(current)) {
      _emit(_T.space, chars.grabWhile(_isWhiteSpace));
      return _word;
    }
    if (current == _open) {
      if (_contextFree.isNotEmpty) {
        final end = '$_open$_slash$_contextFree$_close';
        if (chars.grabN(end.length).toLowerCase() == end.toLowerCase()) {
          return _tagState;
        }
      } else if (chars.includes(_close)) {
        return _tagState;
      }
      _emit(_T.word, current);
      chars.skip();
      return _word;
    }
    // Escapes are enabled: \[, \] and \\ stand for the character.
    if (current == _backslash) {
      final next = chars.getNext();
      chars.skip();
      if (next != null &&
          (next == _open || next == _close || next == _backslash)) {
        chars.skip();
        _emit(_T.word, next);
        return _word;
      }
      _emit(_T.word, current);
      return _word;
    }
    final word = chars.grabWhile(
      (c) =>
          c != _open &&
          c != _space &&
          c != _tab &&
          c != _newLine &&
          c != _backslash,
    );
    _emit(_T.word, word);
    return _word;
  }

  void tokenize() {
    var state = _word;
    while (chars.hasNext()) {
      state = switch (state) {
        _tagState => _stateTag(),
        _attrsState => _stateAttrs(),
        _ => _stateWord(),
      };
    }
  }
}

/// `parse(input, { onlyAllowTags, enableEscapeTags: true, contextFreeTags })`.
List<Object> bbobParse(
  String input, {
  required List<String> onlyAllowTags,
  List<String> contextFreeTags = const [],
}) {
  final allowed = onlyAllowTags.map((t) => t.toLowerCase()).toList();
  final nodes = <Object>[];
  final nestedNodes = <Object>[];
  BBTag? active;
  String? activeAttrName;
  final nestedTags = <String>{};
  late final _Lexer lexer;

  bool isTokenNested(String value) {
    if (!nestedTags.contains(value) && lexer.isTokenNested(value)) {
      nestedTags.add(value);
      return true;
    }
    return nestedTags.contains(value);
  }

  bool isTagNested(String name) => nestedTags.contains(name);
  bool isAllowed(String value) =>
      allowed.isEmpty || allowed.contains(value.toLowerCase());

  void flushActive() {
    active = null;
    activeAttrName = null;
  }

  List<Object> target() {
    final last = nestedNodes.lastOrNull;
    return last is BBTag ? last.content : nodes;
  }

  void appendAsString(List<Object> into, BBTag node, [bool nested = true]) {
    into.add(node.toTagStart());
    if (node.content.isNotEmpty) {
      into.addAll(node.content);
      if (nested) into.add(node.toTagEnd());
    }
  }

  void append(Object node) {
    final into = target();
    if (node is BBTag) {
      if (isAllowed(node.tag)) {
        into.add(node.copy());
      } else {
        appendAsString(into, node);
      }
    } else {
      into.add(node);
    }
  }

  void onToken(_Token token) {
    if (token.isTag) {
      if (!token.isEnd) {
        flushActive();
        final node = BBTag(token.value, {}, []);
        final nested = isTokenNested(token.value);
        active = node;
        if (nested) {
          nestedNodes.add(node);
        } else {
          append(node);
        }
      } else {
        final name = token.value.substring(1);
        final last = nestedNodes.isEmpty ? null : nestedNodes.removeLast();
        flushActive();
        if (last != null) {
          append(last);
        } else if (!isTagNested(name)) {
          append(token.toString());
        }
      }
      return;
    }
    final node = active;
    if (node != null) {
      switch (token.type) {
        case _T.attrName:
          activeAttrName = token.value;
          if (token.value.isNotEmpty) node.attrs[token.value] = '';
        case _T.attrValue:
          final name = activeAttrName;
          if (name != null && name.isNotEmpty) {
            node.attrs[name] = token.value;
            activeAttrName = null;
          } else {
            node.attrs[token.value] = token.value;
          }
        case _T.space || _T.newLine || _T.word:
          if (isTagNested(token.toString())) {
            node.content.add(token.value);
          } else {
            append(token.value);
          }
        case _T.tag:
          append(token.toString());
      }
    } else if (token.isText) {
      append(token.value);
    }
  }

  lexer = _Lexer(
    input,
    onToken,
    contextFreeTags: [for (final tag in contextFreeTags) tag.toLowerCase()],
  );
  lexer.tokenize();
  // Tags opened but never closed: flushed into their parent.
  do {
    final node = nestedNodes.isEmpty ? null : nestedNodes.removeLast();
    if (node is BBTag && isTagNested(node.tag)) {
      appendAsString(target(), node, false);
    } else if (node != null) {
      append(node);
    }
  } while (nestedNodes.isNotEmpty);
  return nodes;
}
