import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../chart_editor/project.dart';
import '../community/community_widgets.dart';
import '../core/account_resource.dart';
import '../core/app_state.dart';
import '../core/managed_media_player.dart';
import '../ui/account_dialog.dart';
import '../ui/detail.dart';
import 'controller.dart';

class AdminPostReview extends StatefulWidget {
  const AdminPostReview({
    super.key,
    required this.controller,
    required this.id,
    required this.facts,
    required this.move,
    this.comment = false,
  });
  final AdminController controller;
  final String id;
  final bool comment;
  final Widget Function(ChartMap, {String prefix}) facts;
  final Future<void> Function(ChartMap) move;
  @override
  State<AdminPostReview> createState() => _AdminPostReviewState();
}

class _AdminPostReviewState extends State<AdminPostReview> {
  ChartMap? _document;
  bool _loading = true;
  String? _paging;
  Object? _error;
  AdminController get c => widget.controller;
  String t(String key) => AppScope.of(context).text('admin.page.$key');
  String get _kind => widget.comment ? 'comments' : 'posts';
  String get _path => '/api/v1/admin/$_kind/${Uri.encodeComponent(widget.id)}';
  ChartMap get _record =>
      chartMap(_document?[widget.comment ? 'comment' : 'post'] ?? const {});
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      ChartMap? current, history;
      if (widget.comment) {
        history = await c.request('$_path/history');
      } else {
        current = await c.request(_path);
        try {
          history = await c.request('$_path/history');
        } catch (error) {
          if (mounted) setState(() => _error = error);
        }
      }
      if (!mounted) return;
      setState(
        () => _document = {
          ...?history,
          ...?current,
          if (current != null)
            'post': {
              ...chartMap(history?['post'] ?? const {}),
              ...chartMap(current['post']),
            },
        },
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more(String section) async {
    final cursor = chartMap(_document!['nextCursors'])[section];
    setState(() {
      _paging = section;
      _error = null;
    });
    try {
      final page = await c.request(
        Uri(
          path: '$_path/history',
          queryParameters: {
            'section': section,
            'cursor': '$cursor',
            'limit': '50',
          },
        ).toString(),
      );
      if (!mounted) return;
      setState(
        () => _document = {
          ..._document!,
          section: [
            ...chartRows(_document![section]),
            ...chartRows(page[section]),
          ],
          'nextCursors': {
            ...chartMap(_document!['nextCursors']),
            section: page['nextCursor'],
          },
        },
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _paging = null);
    }
  }

  Future<void> _state(String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AccountDialog(
        child: AlertDialog(
          title: Text(t('history.$action')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppScope.of(context).text('common.actions.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppScope.of(context).text('common.actions.confirm')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await c.postState(_record, action, comment: widget.comment);
    if (mounted && c.error == null) await _load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final record = _record;
      final unavailable =
          _loading ||
          _paging != null ||
          c.busy ||
          record.isEmpty ||
          record['deletedAt'] != null;
      return AlertDialog(
        title: Text(
          widget.comment
              ? t('history.commentHistory')
              : '${record['title'] ?? t('workspace.reviewPost')}',
        ),
        content: SizedBox(
          width: 840,
          child: _loading && _document == null
              ? const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Symbols.refresh_rounded),
                          label: Text(t('retry')),
                        ),
                      widget.facts(record),
                      if ((record['authorId'] ??
                              chartMap(record['author'] ?? const {})['id'])
                          case final String authorId)
                        ListTile(
                          leading: const Icon(Symbols.person_rounded),
                          title: Text(t('columns.author')),
                          subtitle: Text(
                            '${record['authorName'] ?? chartMap(record['author'] ?? const {})['displayName'] ?? record['authorAccountName'] ?? chartMap(record['author'] ?? const {})['accountName'] ?? authorId}',
                          ),
                          trailing: const Icon(Symbols.chevron_right_rounded),
                          onTap: () {
                            Navigator.pop(context);
                            c.select('users', filters: {'q': authorId});
                          },
                        ),
                      if (record['body'] case final String body)
                        CommunityBody(source: body),
                      if (!widget.comment) ...[
                        _attachments(record['attachments']),
                        if (record['moderation'] is Map)
                          DetailFold(
                            title: t('columns.moderation'),
                            child: widget.facts(
                              chartMap(record['moderation']),
                              prefix: 'history',
                            ),
                          ),
                      ],
                      for (final section in [
                        'revisions',
                        'stateEvents',
                        if (!widget.comment) 'comments',
                      ])
                        DetailFold(
                          title: t('history.$section'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final row in chartRows(
                                _document?[section] ?? const [],
                              )) ...[
                                if (section == 'comments')
                                  ListTile(
                                    title: Text(
                                      '${chartMap(row['author'] ?? const {})['displayName'] ?? chartMap(row['author'] ?? const {})['accountName'] ?? row['id']}',
                                    ),
                                    subtitle: Text(
                                      '${row['body'] ?? row['moderationStatus'] ?? ''}',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: const Icon(
                                      Symbols.chevron_right_rounded,
                                    ),
                                    onTap: () => showDialog<void>(
                                      context: context,
                                      builder: (context) => AccountDialog(
                                        child: AdminPostReview(
                                          controller: c,
                                          id: '${row['id']}',
                                          comment: true,
                                          facts: widget.facts,
                                          move: widget.move,
                                        ),
                                      ),
                                    ),
                                  )
                                else ...[
                                  widget.facts(row, prefix: 'history'),
                                  if (row['body'] case final String body)
                                    CommunityBody(source: body),
                                  _attachments(row['attachments']),
                                  if (row['ipDetails'] is Map)
                                    DetailFold(
                                      title: t('ip.details'),
                                      child: widget.facts(
                                        chartMap(row['ipDetails']),
                                        prefix: 'ip',
                                      ),
                                    ),
                                ],
                                const Divider(),
                              ],
                              if (chartMap(
                                    _document?['nextCursors'] ?? const {},
                                  )[section] !=
                                  null)
                                TextButton(
                                  onPressed: _paging != null || _loading
                                      ? null
                                      : () => _more(section),
                                  child: Text(t('loadMore')),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          if (widget.comment)
            TextButton(
              onPressed: unavailable
                  ? null
                  : () =>
                        _state(record['hiddenAt'] == null ? 'hide' : 'unhide'),
              child: Text(
                t(
                  record['hiddenAt'] == null
                      ? 'history.hide'
                      : 'history.unhide',
                ),
              ),
            )
          else ...[
            TextButton(
              onPressed: unavailable
                  ? null
                  : () => _state(
                      record['status'] == 'hidden' ? 'unhide' : 'hide',
                    ),
              child: Text(
                t(
                  record['status'] == 'hidden'
                      ? 'history.unhide'
                      : 'history.hide',
                ),
              ),
            ),
            TextButton(
              onPressed: unavailable
                  ? null
                  : () => _state(
                      record['commentsLockedAt'] == null ? 'lock' : 'unlock',
                    ),
              child: Text(
                t(
                  record['commentsLockedAt'] == null
                      ? 'history.lock'
                      : 'history.unlock',
                ),
              ),
            ),
            TextButton(
              onPressed: unavailable
                  ? null
                  : () async {
                      await widget.move(record);
                      if (mounted) await _load();
                    },
              child: Text(t('forum.movePost')),
            ),
          ],
          TextButton(
            onPressed: _loading || c.busy ? null : _load,
            child: Text(t('refresh')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppScope.of(context).text('common.actions.close')),
          ),
        ],
      );
    },
  );

  Widget _attachments(Object? value) {
    final rows = chartRows(value ?? const []);
    return rows.isEmpty
        ? const SizedBox.shrink()
        : DetailFold(
            title: t('workspace.attachments'),
            child: Column(
              children: [
                for (final row in rows)
                  _AdminAttachment(
                    key: ValueKey((row['id'], row['contentUrl'])),
                    attachment: row,
                    facts: widget.facts,
                  ),
              ],
            ),
          );
  }
}

class _AdminAttachment extends StatefulWidget {
  const _AdminAttachment({
    super.key,
    required this.attachment,
    required this.facts,
  });
  final ChartMap attachment;
  final Widget Function(ChartMap, {String prefix}) facts;
  @override
  State<_AdminAttachment> createState() => _AdminAttachmentState();
}

class _AdminAttachmentState extends State<_AdminAttachment> {
  AccountResourceLease? _lease;
  Player? _player;
  VideoController? _video;
  StreamSubscription<String>? _errors;
  bool _loading = false;
  Object? _error;
  String? _text;
  final _cancelled = Completer<void>();
  String t(String key) => AppScope.of(context).text('admin.page.$key');
  late final ChartMap _media = () {
    final original = widget.attachment;
    if (RegExp(r'^(image|audio|video)/').hasMatch('${original['mediaType']}')) {
      return original;
    }
    final variants = chartRows(original['variants'] ?? const []);
    return [
          for (final kind in ['media', 'moderation', 'poster', 'thumb'])
            ...variants.where(
              (v) =>
                  v['kind'] == kind &&
                  RegExp(r'^(image|audio|video)/')
                      .hasMatch('${v['mediaType']}'),
            ),
        ].firstOrNull ??
        original;
  }();

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    AccountResourceLease? lease;
    try {
      final uri = Uri.parse('https://haneoka.org')
          .resolve('${_media['contentUrl']}');
      lease = await AccountResources.instance.acquire(
        uri,
        cancelled: _cancelled.future,
      );
      if (!mounted) return;
      if (RegExp(r'^(audio|video)/').hasMatch('${_media['mediaType']}')) {
        await AppScope.of(context).audio.pause();
        if (!mounted) return;
        final player = ManagedMediaPlayer();
        _errors = player.stream.error.listen((error) {
          if (mounted) setState(() => _error = error);
        });
        _player = player;
        _video = VideoController(player);
        await player.open(Media(lease.file.uri.toString()));
      } else if (_media['mediaType'] == 'text/plain') {
        _text = utf8.decode(
          await lease.file
              .openRead(0, 200000)
              .fold<List<int>>([], (v, bytes) => v..addAll(bytes)),
          allowMalformed: true,
        );
      }
      if (!mounted) return;
      _lease = lease;
      lease = null;
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      await lease?.release();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final epoch = AccountResources.instance.epoch;
    AccountResourceLease? lease;
    try {
      lease = await AccountResources.instance.acquire(
        Uri.parse('https://haneoka.org')
            .resolve('${widget.attachment['contentUrl']}'),
        cancelled: _cancelled.future,
      );
      final bytes = await lease.file.readAsBytes();
      if (!mounted || epoch != AccountResources.instance.epoch) return;
      await FilePicker.saveFile(
        fileName: '${widget.attachment['fileName']}',
        bytes: bytes,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      await lease?.release();
    }
  }

  @override
  void dispose() {
    _cancelled.complete();
    _errors?.cancel();
    final player = _player, lease = _lease;
    unawaited(() async {
      await player?.dispose();
      await lease?.release();
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${widget.attachment['fileName'] ?? widget.attachment['id']}',
        style: Theme.of(context).textTheme.titleSmall,
      ),
      widget.facts(widget.attachment, prefix: 'history'),
      if (_error != null) Text(t('workspace.previewUnavailable')),
      if (_lease != null && '${_media['mediaType']}'.startsWith('image/'))
        ImageGallery(
          images: const [],
          entries: [
            GalleryImage(
              'https://haneoka.org${_media['contentUrl']}',
              '${widget.attachment['fileName']}',
              localized: false,
            ),
          ],
          natural: true,
        ),
      if (_video != null)
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Video(controller: _video!),
        ),
      if (_text != null) SelectableText(_text!),
      Wrap(
        spacing: 8,
        children: [
          if (_media['contentUrl'] != null)
            TextButton.icon(
              onPressed: _loading || _lease != null ? null : _open,
              icon: const Icon(Symbols.visibility_rounded),
              label: Text(t('creations.open')),
            ),
          if (widget.attachment['contentUrl'] != null)
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Symbols.download_rounded),
              label: Text(AppScope.of(context).text('common.actions.download')),
            ),
        ],
      ),
      const Divider(),
    ],
  );
}
