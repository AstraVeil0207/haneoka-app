import 'bbob.dart';

/// The website's community markup (`lib/community-markup.ts`): BBCode-style
/// tags rendered to the same HTML the site renders.
const _tags = [
  'b',
  'i',
  'u',
  's',
  'quote',
  'code',
  'spoiler',
  'list',
  '*',
  'li',
  'url',
  'sticker',
  'h2',
  'h3',
  'h4',
  'align',
  'highlight',
  'hr',
];
const _blockTags = {
  'quote',
  'code',
  'spoiler',
  'list',
  'li',
  'h2',
  'h3',
  'h4',
  'align',
  'hr',
};

String escapeMarkup(String value) => value.replaceAllMapped(
  RegExp(r'''[&<>"']'''),
  (m) => const {
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  }[m[0]]!,
);

/// An http(s) address as `new URL(value).href`, or empty.
String safeCommunityLink(String value) {
  final text = value.trim();
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty ||
      RegExp(r'\s').hasMatch(text)) {
    return '';
  }
  final normal = uri.path.isEmpty ? uri.replace(path: '/') : uri;
  return normal.toString();
}

/// `^[a-z0-9][a-z0-9-]{0,31}:\d{1,12}(?::lang)?$`: server, stamp id, language.
bool validStickerToken(String value) => RegExp(
  r'^[a-z0-9][a-z0-9-]{0,31}:\d{1,12}(?::[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*)?$',
).hasMatch(value);

String _attribute(BBTag node) => node.attrs.values.firstOrNull ?? '';

List<Object> _tree(String source) {
  if (source.length > 20000) return [source];
  final nodes = bbobParse(
    source,
    onlyAllowTags: _tags,
    contextFreeTags: const ['code'],
  );
  final stack = [for (final node in nodes) (node, 0)];
  var count = 0;
  while (stack.isNotEmpty) {
    final (node, depth) = stack.removeLast();
    if (++count > 24000 || depth > 40) return [source];
    if (node is BBTag) {
      for (final child in node.content) {
        stack.add((child, depth + 1));
      }
    }
  }
  return nodes;
}

String _literal(List<Object> nodes) => nodes
    .map((node) => node is BBTag ? _literal(node.content) : '$node')
    .join();

/// The post or comment body as HTML. Stickers become
/// `<community-sticker token locale label>` elements.
String communityMarkup(
  String source, {
  String spoiler = 'Spoiler',
  String locale = 'en',
  bool allowStickers = true,
}) {
  late String Function(Object node, [String align]) render;
  String flow(List<Object> nodes, [String align = '']) {
    final blocks = <String>[];
    var inline = '';
    void flush() {
      final text = inline.replaceAll(RegExp(r'^\n+|\n+$'), '');
      if (text.isNotEmpty) {
        for (final part in text.split('\n\n')) {
          final body = part.replaceAll('\n', '<br>');
          blocks.add(
            '<p${align.isNotEmpty ? ' style="text-align:$align"' : ''}>'
            '${body.isEmpty ? '<br>' : body}</p>',
          );
        }
      }
      inline = '';
    }

    for (final node in nodes) {
      if (node is BBTag && _blockTags.contains(node.tag.toLowerCase())) {
        flush();
        blocks.add(render(node, align));
      } else {
        inline += render(node);
      }
    }
    flush();
    return blocks.join();
  }

  String inline(List<Object> nodes) => nodes.map((n) => render(n)).join();

  render = (Object node, [String align = '']) {
    if (node is! BBTag) return escapeMarkup('$node');
    final tag = node.tag.toLowerCase();
    const marks = {'b': 'strong', 'i': 'em', 'u': 'u', 's': 's'};
    if (marks[tag] case final mark?) {
      return '<$mark>${inline(node.content)}</$mark>';
    }
    if (tag == 'align') {
      final value = _attribute(node);
      return flow(
        node.content,
        const {'left', 'center', 'right', 'justify'}.contains(value)
            ? value
            : '',
      );
    }
    if (const {'h2', 'h3', 'h4'}.contains(tag)) {
      return '<$tag${align.isNotEmpty ? ' style="text-align:$align"' : ''}>'
          '${inline(node.content)}</$tag>';
    }
    if (tag == 'hr') return '<hr>';
    if (tag == 'highlight') return '<mark>${inline(node.content)}</mark>';
    if (tag == 'quote') return '<blockquote>${flow(node.content)}</blockquote>';
    if (tag == 'code') {
      return '<pre><code>${escapeMarkup(_literal(node.content))}</code></pre>';
    }
    if (tag == 'spoiler') {
      return '<details data-spoiler><summary>${escapeMarkup(spoiler)}</summary>'
          '<div>${flow(node.content)}</div></details>';
    }
    if (tag == 'url') {
      final value = _attribute(node);
      final href = safeCommunityLink(
        value.isNotEmpty ? value : _literal(node.content),
      );
      return href.isNotEmpty
          ? '<a href="${escapeMarkup(href)}" target="_blank" '
                'rel="nofollow noopener noreferrer">${inline(node.content)}</a>'
          : inline(node.content);
    }
    if (tag == 'sticker') {
      if (!allowStickers) return inline(node.content);
      final token = _attribute(node);
      return validStickerToken(token)
          ? '<community-sticker token="${escapeMarkup(token)}" '
                'locale="${escapeMarkup(locale)}" '
                'label="${escapeMarkup(_literal(node.content))}">'
                '</community-sticker>'
          : inline(node.content);
    }
    if (tag == 'list') {
      final groups = <List<Object>>[];
      for (final child in node.content) {
        if (child is BBTag && child.tag == '*') {
          groups.add([...child.content]);
        } else if (child is BBTag && child.tag == 'li') {
          groups.add(child.content);
        } else if (groups.isNotEmpty) {
          groups.last.add(child);
        } else if (child is BBTag || '$child'.trim().isNotEmpty) {
          groups.add([child]);
        }
      }
      final list = _attribute(node) == '1' ? 'ol' : 'ul';
      return '<$list>${groups.map((g) => '<li>${flow(g)}</li>').join()}</$list>';
    }
    return inline(node.content);
  };
  return flow(_tree(source));
}

/// The body as one line of plain text.
String communityExcerpt(String source) =>
    _literal(_tree(source)).replaceAll(RegExp(r'\s+'), ' ').trim();

/// The first sticker outside code and spoilers, for previews.
({String token, String label})? communityStickerPreview(String source) {
  List<Object> visible(List<Object> nodes) => [
    for (final node in nodes)
      if (node is! BBTag)
        node
      else if (!const {'code', 'spoiler'}.contains(node.tag.toLowerCase()))
        BBTag(node.tag, node.attrs, visible(node.content)),
  ];
  final pending = [..._tree(source)].reversed.toList();
  while (pending.isNotEmpty) {
    final node = pending.removeLast();
    if (node is! BBTag) continue;
    final tag = node.tag.toLowerCase();
    if (tag == 'code' || tag == 'spoiler') continue;
    if (tag == 'sticker') {
      final token = _attribute(node);
      if (validStickerToken(token)) {
        return (token: token, label: _literal(visible(node.content)));
      }
    }
    pending.addAll(node.content.reversed);
  }
  return null;
}
