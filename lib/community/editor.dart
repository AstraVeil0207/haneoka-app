import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:material_symbols_icons/symbols.dart';

import '../account/haneoka_account.dart';
import '../core/app_state.dart';
import '../core/net.dart';
import '../core/i18n.dart';
import '../shell/page.dart';
import '../ui/app_image.dart';
import '../ui/theme.dart';
import '../ui/tile.dart';
import 'community_widgets.dart';
import 'post_screen.dart';
import 'sections.dart';

Object? _decode(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

/// `\`, `[` and `]` escaped for markup text (`escapeText`).
String escapeMarkupText(String text) =>
    text.replaceAll('\\', '\\\\').replaceAll('[', '\\[').replaceAll(']', '\\]');

/// The game's stickers, Japanese and international together, for the
/// editors' sticker picker (`openStamps`).
Future<List<Json>> loadStickers(AppState state) async {
  final entries = <String, Json>{};
  for (final server in {state.server, 'intl', 'jp'}) {
    try {
      final catalog = jsonMap(await state.apiFor(server).catalog('stamps'));
      for (final MapEntry(key: id, value: value) in catalog.entries) {
        final stamp = jsonMap(value);
        final stampId = '${stamp['stampId'] ?? id}';
        if (stamp.isEmpty ||
            entries.containsKey(id) ||
            !RegExp(r'^\d{1,12}$').hasMatch(stampId)) {
          continue;
        }
        entries[id] = {...stamp, 'stampId': stampId, 'sourceServer': server};
      }
    } catch (_) {}
  }
  return entries.values.toList()..sort(
    (a, b) => (int.tryParse('${a['stampId']}') ?? 0).compareTo(
      int.tryParse('${b['stampId']}') ?? 0,
    ),
  );
}

/// Picks a sticker and returns its markup:
/// `[sticker=server:id:locale]name[/sticker]`.
Future<String?> pickSticker(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _StickerSheet(),
    );

class _StickerSheet extends StatefulWidget {
  const _StickerSheet();
  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  Future<List<Json>>? _stickers;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stickers ??= loadStickers(AppScope.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppScope.of(context).text;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: FutureBuilder(
        future: _stickers,
        builder: (context, snapshot) {
          final stickers = snapshot.data;
          if (stickers == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (stickers.isEmpty) {
            return Center(
              child: Text(
                communityLabel(context, 'stickersUnavailable', 'Unavailable'),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 80,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: stickers.length,
            itemBuilder: (context, index) {
              final stamp = stickers[index];
              final label = t.text(stamp['name']);
              final token =
                  '${stamp['sourceServer']}:${stamp['stampId']}:${t.locale}';
              final image = '${stamp['image'] ?? ''}';
              return Tooltip(
                message: label,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Corner.small),
                  onTap: () => Navigator.of(
                    context,
                  ).pop('[sticker=$token]${escapeMarkupText(label)}[/sticker]'),
                  child: image.isEmpty
                      ? Center(child: Text(label, maxLines: 2))
                      : AppImage(
                          candidates: [absoluteUrl(image)],
                          fit: BoxFit.contain,
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Markup buttons over a text field: wrap the selection in a tag, or insert
/// a sticker at the cursor.
class MarkupToolbar extends StatelessWidget {
  const MarkupToolbar({super.key, required this.controller, this.full = false});
  final TextEditingController controller;

  /// Headings, lists, quotes and spoilers too, for posts.
  final bool full;

  void _insert(String text) {
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final next = value.text.replaceRange(selection.start, selection.end, text);
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
  }

  void _wrap(String open, String close) {
    final value = controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final inner = selection.textInside(value.text);
    final next = value.text.replaceRange(
      selection.start,
      selection.end,
      '$open$inner$close',
    );
    controller.value = TextEditingValue(
      text: next,
      selection: inner.isEmpty
          ? TextSelection.collapsed(offset: selection.start + open.length)
          : TextSelection(
              baseOffset: selection.start,
              extentOffset:
                  selection.start + open.length + inner.length + close.length,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tools = <(IconData, VoidCallback)>[
      (Symbols.format_bold_rounded, () => _wrap('[b]', '[/b]')),
      (Symbols.format_italic_rounded, () => _wrap('[i]', '[/i]')),
      (Symbols.format_underlined_rounded, () => _wrap('[u]', '[/u]')),
      (Symbols.strikethrough_s_rounded, () => _wrap('[s]', '[/s]')),
      (Symbols.link_rounded, () => _wrap('[url=https://]', '[/url]')),
      if (full) ...[
        (Symbols.format_h2_rounded, () => _wrap('[h2]', '[/h2]')),
        (
          Symbols.format_list_bulleted_rounded,
          () => _wrap('[list]\n[*]', '\n[/list]'),
        ),
        (Symbols.format_quote_rounded, () => _wrap('[quote]', '[/quote]')),
        (Symbols.code_rounded, () => _wrap('[code]', '[/code]')),
        (
          Symbols.format_ink_highlighter_rounded,
          () => _wrap('[highlight]', '[/highlight]'),
        ),
      ],
      (Symbols.visibility_off_rounded, () => _wrap('[spoiler]', '[/spoiler]')),
      (
        Symbols.add_reaction_rounded,
        () async {
          final sticker = await pickSticker(context);
          if (sticker != null) _insert(sticker);
        },
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (icon, onPressed) in tools)
            IconButton(icon: Icon(icon), onPressed: onPressed),
        ],
      ),
    );
  }
}

/// One picked file on its way to becoming an attachment.
class _Upload {
  _Upload(this.name, this.bytes, this.mediaType);
  final String name;
  final Uint8List bytes;
  final String mediaType;
  Json? attachment;
  double progress = 0;
  String? error;
  bool get ready =>
      attachment != null &&
      const {'ready', 'scanning', 'review'}.contains(attachment!['status']) &&
      const {
        'allow',
        'pending',
        'review',
      }.contains(attachment!['moderationStatus']);
}

const _mediaTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'mp4': 'video/mp4',
  'webm': 'video/webm',
  'mov': 'video/quicktime',
};

/// Writing a post (`renderPostEditor`): the forum, a title, the body with
/// markup and stickers, images and videos, tags and who can see it.
class PostEditorScreen extends StatefulWidget {
  const PostEditorScreen({super.key, this.forum});
  final Json? forum;
  @override
  State<PostEditorScreen> createState() => _PostEditorScreenState();
}

class _PostEditorScreenState extends State<PostEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tags = TextEditingController();
  String _visibility = 'public';
  String? _forumId;
  List<Json> _forums = [];
  final _uploads = <_Upload>[];
  bool _preview = false;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _forumId = widget.forum?['id'] as String?;
    communityRequest('GET', '/api/v1/community/forums').then((data) {
      if (!mounted) return;
      setState(() {
        _forums = [
          for (final forum in jsonList(data['forums']))
            if (jsonMap(forum['capabilities'])['canPost'] == true &&
                forum['isInternal'] != true)
              forum,
        ];
        if (!_forums.any((f) => f['id'] == _forumId)) {
          _forumId = _forums.firstOrNull?['id'] as String?;
        }
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    super.dispose();
  }

  /// Tags written as #tag in the body and in the tags field (`postTags`).
  List<String>? _postTags() {
    final explicit = _tags.text
        .split(RegExp(r'[\s,#，]+'))
        .map((tag) => tag.trim().toLowerCase())
        .where((tag) => tag.isNotEmpty);
    final withoutCode = _body.text.replaceAll(
      RegExp(
        r'\[code(?:=[^\]\r\n]{0,512})?\][\s\S]*?\[/code\]',
        caseSensitive: false,
      ),
      ' ',
    );
    final found = RegExp(
      r'(?:^|[^\p{L}\p{N}_])#([\p{L}\p{N}][\p{L}\p{N}_-]{0,31})(?![\p{L}\p{N}_-])',
      unicode: true,
    ).allMatches(withoutCode).map((m) => m[1]!.toLowerCase());
    final tags = {...found, ...explicit}.toList();
    final valid = RegExp(r'^[\p{L}\p{N}][\p{L}\p{N}_-]*$', unicode: true);
    return tags.length <= 10 &&
            tags.every((tag) => tag.runes.length <= 32 && valid.hasMatch(tag))
        ? tags
        : null;
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: _mediaTypes.keys.toList(),
    );
    if (result == null || !mounted) return;
    for (final file in result.files) {
      final type = _mediaTypes[(file.extension ?? '').toLowerCase()];
      final bytes =
          file.bytes ??
          (file.path != null ? await File(file.path!).readAsBytes() : null);
      if (type == null || bytes == null) continue;
      final upload = _Upload(file.name, bytes, type);
      setState(() => _uploads.add(upload));
      unawaited(_upload(upload));
    }
  }

  Future<http.Response> _put(String path, Uint8List bytes, String type) async {
    final request = http.Request('PUT', Uri.parse(absoluteUrl(path)))
      ..headers.addAll({
        'Content-Type': type,
        'Origin': communityOrigin,
        ...HaneokaAccount.instance.authorization,
      })
      ..bodyBytes = bytes;
    return http.Response.fromStream(await netClient.send(request));
  }

  /// Reserve, send (in parts when the server asks), then wait for the
  /// server to accept it (`uploadCommunityAttachment`).
  Future<void> _upload(_Upload upload) async {
    try {
      final intent = await communityRequest(
        'POST',
        '/api/v1/community/uploads/intents',
        body: {
          'fileName': upload.name,
          'mediaType': upload.mediaType,
          'size': upload.bytes.length,
        },
      );
      var attachment = jsonMap(intent['attachment']).isNotEmpty
          ? jsonMap(intent['attachment'])
          : intent;
      final multipart = jsonMap(attachment['multipart']);
      if (multipart.isEmpty) {
        final response = await _put(
          '${attachment['uploadUrl']}',
          upload.bytes,
          '${attachment['mediaType'] ?? upload.mediaType}',
        );
        if (response.statusCode >= 300) throw Exception(response.statusCode);
      } else {
        final size = (multipart['partSize'] as num).toInt();
        final count = (multipart['partCount'] as num).toInt();
        final parts = <Json>[];
        for (var number = 1; number <= count; number++) {
          final start = (number - 1) * size;
          final end = (number * size).clamp(0, upload.bytes.length);
          final response = await _put(
            '${multipart['partUploadUrl']}'.replaceFirst(
              '{partNumber}',
              '$number',
            ),
            Uint8List.sublistView(upload.bytes, start, end),
            'application/octet-stream',
          );
          if (response.statusCode >= 300) throw Exception(response.statusCode);
          final part = jsonMap(jsonMap(_decode(response.body))['part']);
          parts.add({'partNumber': number, 'etag': part['etag']});
          if (mounted) setState(() => upload.progress = number / count);
        }
        await communityRequest(
          'POST',
          '${multipart['completeUrl']}',
          body: {'parts': parts},
        );
      }
      if (mounted) setState(() => upload.progress = 1);
      // Accepted once scanned or queued for review.
      for (var attempt = 0; attempt < 60; attempt++) {
        final status = await communityRequest(
          'GET',
          '/api/v1/community/attachments/${Uri.encodeComponent('${attachment['id']}')}',
        );
        attachment = jsonMap(status['attachment']).isNotEmpty
            ? jsonMap(status['attachment'])
            : status;
        upload.attachment = attachment;
        if (upload.ready || attachment['status'] == 'failed') break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (mounted) {
        setState(() {
          if (!upload.ready) {
            upload.error = communityLabel(
              context,
              'uploadFailed',
              'Upload failed',
            );
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => upload.error = communityLabel(
            context,
            'unavailable',
            'Unavailable',
          ),
        );
      }
    }
  }

  Future<void> _publish() async {
    String label(String key, String fallback) =>
        communityLabel(context, key, fallback);
    if (_forumId == null) {
      setState(
        () => _error = label(
          'forumChooseWritable',
          'Choose a forum where you can post.',
        ),
      );
      return;
    }
    final body = _body.text.trim();
    if (body.isEmpty || body.length > 20000) {
      setState(
        () => _error = label(
          'invalidBody',
          'Write between 1 and 20,000 characters.',
        ),
      );
      return;
    }
    final tags = _postTags();
    if (tags == null) {
      setState(
        () => _error = label(
          'invalidTags',
          'Use up to 10 tags of at most 32 letters, numbers, underscores, or hyphens.',
        ),
      );
      return;
    }
    if (_uploads.any((u) => !u.ready && u.error == null)) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final result = await communityRequest(
        'POST',
        '/api/v1/community/posts',
        body: {
          'title': _title.text.trim(),
          'body': body,
          'visibility': _visibility,
          'tags': tags,
          'forumId': _forumId,
          'attachmentIds': [
            for (final upload in _uploads)
              if (upload.ready) upload.attachment!['id'],
          ],
        },
      );
      final id = jsonMap(result['post'])['id'] ?? result['id'];
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => PostScreen(id: '$id')),
      );
    } on AccountError catch (error) {
      if (mounted) setState(() => _error = error.code);
    } catch (_) {
      if (mounted) setState(() => _error = label('unavailable', 'Unavailable'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = AppScope.of(context).text;
    String label(String key, String fallback) =>
        communityLabel(context, key, fallback);
    return ShellPage(
      title: label('newPost', 'New post'),
      body: ListView(
        padding: pagePadding(context),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownMenu<String>(
                    expandedInsets: EdgeInsets.zero,
                    label: Text(label('forums', 'Forums')),
                    initialSelection: _forumId,
                    leadingIcon: Icon(
                      forumIcon(
                        _forums
                            .where((f) => f['id'] == _forumId)
                            .firstOrNull?['icon'],
                      ),
                    ),
                    onSelected: (id) => setState(() => _forumId = id),
                    dropdownMenuEntries: [
                      for (final forum in _forums)
                        DropdownMenuEntry(
                          value: '${forum['id']}',
                          label: _name(forum, t),
                          leadingIcon: Icon(forumIcon(forum['icon'])),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _title,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: label('postTitle', 'Title'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: MarkupToolbar(controller: _body, full: true),
                      ),
                      IconButton(
                        isSelected: _preview,
                        tooltip: label('preview', 'Preview'),
                        onPressed: () => setState(() => _preview = !_preview),
                        icon: const Icon(Symbols.preview_rounded),
                      ),
                    ],
                  ),
                  if (_preview)
                    Container(
                      constraints: const BoxConstraints(minHeight: 200),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: scheme.outline),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: CommunityBody(source: _body.text),
                    )
                  else
                    TextField(
                      controller: _body,
                      minLines: 8,
                      maxLines: null,
                      maxLength: 20000,
                      decoration: InputDecoration(
                        hintText: label(
                          'postBody',
                          'What would you like to share?',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final upload in _uploads)
                        _UploadTile(
                          upload: upload,
                          onRemove: () =>
                              setState(() => _uploads.remove(upload)),
                        ),
                      OutlinedButton.icon(
                        onPressed: _pick,
                        icon: const Icon(Symbols.add_photo_alternate_rounded),
                        label: Text(label('addAttachment', 'Attach')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tags,
                    decoration: InputDecoration(
                      labelText: label('tags', 'Tags'),
                      prefixText: '#',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final value in const [
                        'public',
                        'protected',
                        'private',
                      ])
                        ButtonSegment(
                          value: value,
                          label: Text(
                            label(
                              'visibility${value[0].toUpperCase()}${value.substring(1)}',
                              value,
                            ),
                          ),
                        ),
                    ],
                    selected: {_visibility},
                    onSelectionChanged: (v) =>
                        setState(() => _visibility = v.single),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_error, style: TextStyle(color: scheme.error)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _publish,
                    icon: const Icon(Symbols.send_rounded),
                    label: Text(
                      _busy
                          ? label('publishing', 'Publishing…')
                          : label('publish', 'Publish'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _name(Json forum, SiteText t) {
    final names = jsonMap(forum['names']);
    return '${names[t.locale] ?? names['en'] ?? forum['defaultName'] ?? ''}';
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({required this.upload, required this.onRemove});
  final _Upload upload;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      height: 96,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Corner.small),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: scheme.surfaceContainerHighest),
            if (upload.mediaType.startsWith('image/'))
              Image.memory(upload.bytes, fit: BoxFit.cover)
            else
              const Icon(Symbols.movie_rounded, size: 36),
            if (!upload.ready && upload.error == null)
              Center(
                child: CircularProgressIndicator(
                  value: upload.progress > 0 && upload.progress < 1
                      ? upload.progress
                      : null,
                ),
              ),
            if (upload.error != null)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Icon(Symbols.error_rounded, color: scheme.error),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                color: Colors.white,
                iconSize: 18,
                onPressed: onRemove,
                icon: const Icon(Symbols.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
