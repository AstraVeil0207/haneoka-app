import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../account/haneoka_account.dart';
import '../community/community_widgets.dart';
import '../community/media_upload.dart';
import '../community/reactions.dart';
import '../core/app_state.dart';
import '../core/media_lifecycle.dart';
import '../core/resource_file_cache.dart';
import '../core/provider_api.dart';
import '../ui/app_image.dart';
import 'controller.dart';
import 'inspector.dart';
import 'library.dart';
import 'project.dart';
import 'storage.dart';

class ChartPublicationController extends ChangeNotifier {
  ChartPublicationController(this.host) {
    _account.addListener(_accountChanged);
    MediaLifecycle.register(this, close);
  }
  final ChartEditorController host;
  final _account = HaneokaAccount.instance;
  String owner = '', error = '';
  ChartMap draft = {
    'audio': null,
    'cover': null,
    'summary': '',
    'visibility': 'public',
    'remix': true,
  };
  ChartMap? published;
  bool busy = false, ready = false, _closed = false;
  double progress = 0;
  int _epoch = 0;
  CommunityMediaUpload? _upload;
  Future<void>? _operation;
  void changed() {
    if (!_closed) notifyListeners();
  }

  void _accountChanged() {
    if ('${_account.user?['id'] ?? ''}' != owner) unawaited(initialize());
  }

  Future<void> initialize() async {
    final epoch = ++_epoch;
    _upload?.close();
    _upload = null;
    busy = false;
    ready = false;
    await _account.load();
    owner = '${_account.user?['id'] ?? ''}';
    final stored = await host.store.publication(host.id, owner),
        portable = await host.store.publication(host.id, 'portable');
    if (_closed || epoch != _epoch) return;
    final seed = host.project.extensions['communityMedia'];
    final source = seed is Map && seed['audioSha'] == host.media?.ref.sha
        ? seed
        : null;
    draft = stored ?? portable ?? portableChartPublication(source);
    if (draft['audioSha'] != null && draft['audioSha'] != host.media?.ref.sha) {
      draft = {...draft, 'audio': null, 'audioSha': host.media?.ref.sha};
    }
    ready = true;
    error = '';
    changed();
    if (draft['id'] != null && owner.isNotEmpty) {
      try {
        final response = await communityRequest(
          'GET',
          '/api/v1/community/charts/${draft['id']}?draft=1',
        );
        if (_closed || epoch != _epoch) return;
        published = chartMap(response['chart']);
        changed();
      } catch (e) {
        if (!_closed && epoch == _epoch) {
          error = e is AccountError ? e.code : 'service_unavailable';
          changed();
        }
      }
    }
  }

  Future<void> persist() async {
    if (!ready) return;
    await host.store.savePublication(host.id, owner, draft);
  }

  Future<void> update(ChartMap patch) async {
    draft = {...draft, ...patch};
    await persist();
    changed();
  }

  Future<void> setCover(Uint8List bytes, String name, String type) async {
    final extension = type == 'image/jpeg'
        ? 'jpg'
        : type == 'image/webp'
        ? 'webp'
        : 'png';
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const AccountError('cover_format');
    }
    final file = await host.store.saveCover(host.id, bytes, extension);
    await update({
      'cover': null,
      'coverFile': file.path,
      'coverName': name,
      'coverType': type,
      'coverIntent': null,
      'coverKey': chartUuid(),
      'coverUrl': null,
    });
  }

  Future<void> chooseMedia(ChartLibrarySelection selection) async {
    busy = true;
    changed();
    try {
      final api = selection.api, song = selection.song;
      final ref = <String, Object?>{
        'kind': 'server',
        'provider': api is ProviderApi ? 'bestdori' : 'our-notes',
        'server': api is ProviderApi ? api.region : api.server,
        'songId': '${song['musicId']}',
        if (api is! ProviderApi) 'releaseId': await api.release(),
      };
      final uri = api.asset(
        '${song[selection.mode == 'cover' ? 'jacketUrl' : 'musicUrl']}',
      );
      final lease = await resourceFileCache.acquire(
        uri,
        kind: selection.mode == 'cover'
            ? ResourceFileKind.renderResource
            : ResourceFileKind.media,
      );
      try {
        final hash = (await sha256.bind(lease.file.openRead()).first)
            .toString();
        ref['sha256'] = hash;
        if (selection.mode == 'cover') {
          await update({
            'cover': ref,
            'coverFile': null,
            'coverIntent': null,
            'coverUrl': uri.toString(),
          });
        } else {
          await host.loadAudio(lease.file, name: uri.pathSegments.last);
          await update({'audio': ref, 'audioSha': host.media?.ref.sha});
        }
      } finally {
        await lease.release();
      }
    } catch (e) {
      error = e is AccountError ? e.code : 'media_missing';
    } finally {
      if (selection.disposeApi) selection.api.dispose();
      busy = false;
      changed();
    }
  }

  Future<void> save({required bool publish}) {
    if (busy || !ready) return Future.value();
    return _operation = _save(publish);
  }

  Future<void> _save(bool publish) async {
    final epoch = _epoch, capturedOwner = owner, media = host.media;
    if (media == null) return;
    final releaseAudio = media.retain();
    busy = true;
    error = '';
    progress = 0;
    changed();
    final upload = CommunityMediaUpload(
      capturedOwner,
      progress: (value) {
        if (!_closed && epoch == _epoch) {
          progress = value;
          changed();
        }
      },
    );
    _upload = upload;
    try {
      if (capturedOwner.isEmpty) {
        throw const AccountError('authentication_required');
      }
      await host.flush();
      final session = objectOf(
        await _account
            .request('GET', '/api/auth/get-session')
            .timeout(const Duration(seconds: 30)),
      );
      final user = objectOf(session['user']);
      if (user['id'] != capturedOwner) {
        throw const AccountError('account_changed');
      }
      if (user['emailVerified'] != true) {
        throw const AccountError('email_verification_required');
      }
      upload.check();
      draft = {
        ...draft,
        'id': draft['id'] ?? chartUuid(),
        'version': draft['version'] ?? 0,
        'ownerId': capturedOwner,
      };
      await persist();
      final pending = draft['pendingSave'];
      if (pending is Map) {
        final recovered = await upload.request(
          'PUT',
          '/api/v1/community/charts/${draft['id']}',
          body: jsonDecode(pending['body'] as String),
        );
        final chart = chartMap(recovered['chart']);
        draft = {
          ...draft,
          'version': chart['version'],
          'revision': chart['revision'],
        }..remove('pendingSave');
        published = chart;
        await persist();
      }
      if (draft['audio'] == null || draft['audioSha'] != media.ref.sha) {
        final result = await upload.send(
          'POST',
          '/api/v1/community/charts/audio',
          media.waveFile,
          'audio/wav',
        );
        draft = {
          ...draft,
          'audio': {'kind': 'upload', 'id': result['id']},
          'audioSha': media.ref.sha,
        };
        await persist();
      }
      final cover = draft['coverFile'];
      if (cover is String && draft['cover'] == null) {
        try {
          final attachment = await upload.cover(
            File(cover),
            '${draft['coverName'] ?? 'cover.png'}',
            '${draft['coverType'] ?? 'image/png'}',
            '${draft['coverKey'] ??= chartUuid()}',
            previous: draft['coverIntent'] is Map
                ? chartMap(draft['coverIntent'])
                : null,
            persist: (value) async {
              draft = {...draft, 'coverIntent': value};
              await persist();
            },
          );
          draft = {
            ...draft,
            'cover': {'kind': 'upload', 'id': attachment['id']},
          };
          await persist();
        } catch (e) {
          if (publish) rethrow;
          upload.check();
          error = 'media_not_ready';
        }
      }
      if (publish && draft['cover'] == null) {
        throw const AccountError('media_missing');
      }
      upload.check();
      final body =
          <String, Object?>{
              ...draft,
              'project': host.history.value.data,
              'publish': publish,
              'requestId': chartUuid(),
            }
            ..remove('pendingSave')
            ..remove('coverFile')
            ..remove('coverName')
            ..remove('coverType')
            ..remove('coverKey')
            ..remove('coverIntent')
            ..remove('coverUrl');
      draft = {
        ...draft,
        'pendingSave': {'body': jsonEncode(body)},
      };
      await persist();
      final response = await upload.request(
            'PUT',
            '/api/v1/community/charts/${draft['id']}',
            body: body,
          ),
          chart = chartMap(response['chart']);
      if (_closed || epoch != _epoch) return;
      published = chart;
      draft = {
        ...draft,
        'version': chart['version'],
        'revision': chart['revision'],
      }..remove('pendingSave');
      await persist();
    } catch (e) {
      if (!_closed && epoch == _epoch) {
        error = e is AccountError
            ? e.code
            : e is FormatException
            ? e.message
            : 'service_unavailable';
        if (e is AccountError &&
            !const {
              'rate_limit_exceeded',
              'too_many_requests',
              'service_unavailable',
              'storage_failed',
            }.contains(e.code)) {
          draft.remove('pendingSave');
          await persist();
        }
      }
    } finally {
      await releaseAudio();
      upload.close();
      if (identical(_upload, upload)) _upload = null;
      if (!_closed && epoch == _epoch) {
        busy = false;
        changed();
      }
    }
  }

  Future<void> withdraw() async {
    if (draft['id'] == null || busy) return;
    busy = true;
    changed();
    try {
      final result = await communityRequest(
        'POST',
        '/api/v1/community/charts/${draft['id']}/unpublish',
        body: {'version': draft['version']},
      );
      draft = {...draft, 'version': result['version']};
      published = published == null
          ? null
          : {...published!, 'publishedRevision': null};
      await persist();
    } catch (e) {
      error = e is AccountError ? e.code : 'service_unavailable';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ++_epoch;
    _upload?.close();
    _account.removeListener(_accountChanged);
    await _operation;
    MediaLifecycle.unregister(this);
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

Future<void> showChartPublication(
  BuildContext context,
  ChartEditorController host,
) async {
  await host.audio.pause();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ChartPublicationDialog(host: host),
  );
}

class _ChartPublicationDialog extends StatefulWidget {
  const _ChartPublicationDialog({required this.host});
  final ChartEditorController host;
  @override
  State<_ChartPublicationDialog> createState() =>
      _ChartPublicationDialogState();
}

class _ChartPublicationDialogState extends State<_ChartPublicationDialog> {
  late final controller = ChartPublicationController(widget.host)
    ..addListener(_changed);
  String _shownError = '';
  String t(String key) => AppScope.of(context).text('community.charts.$key');
  @override
  void initState() {
    super.initState();
    unawaited(controller.initialize());
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (controller.error.isNotEmpty && controller.error != _shownError) {
      _shownError = controller.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final error = t('errors.${controller.error}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.isEmpty ? t('errors.service_unavailable') : error,
            ),
          ),
        );
      });
    }
    if (controller.error.isEmpty) _shownError = '';
  }

  Future<void> _pickCover() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    if (file == null || !mounted) return;
    final type = file.extension == 'webp'
        ? 'image/webp'
        : const {'jpg', 'jpeg'}.contains(file.extension)
        ? 'image/jpeg'
        : 'image/png';
    try {
      await controller.setCover(await file.readAsBytes(), file.name, type);
    } catch (_) {
      controller.error = 'cover_format';
      controller.changed();
    }
  }

  Future<void> _choose(String kind) async {
    final selected = await openChartLibrary(context, mediaKind: kind);
    if (selected != null && mounted) await controller.chooseMedia(selected);
  }

  Future<void> _save(bool publish) async {
    if (!await requireSession(context) || !mounted) return;
    if (controller.owner.isEmpty) await controller.initialize();
    await controller.save(publish: publish);
    if (mounted && controller.error.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(publish ? 'published' : 'draftSaved'))),
      );
    }
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = controller,
        text = AppScope.of(context).text,
        draft = c.draft,
        cover = draft['coverFile'];
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(t('publishToCommunity'))),
          SizedBox(
            width: 48,
            child: Tooltip(
              message: t('version'),
              child: Text(
                '${c.published?['revision'] ?? '—'}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox.square(
            dimension: 24,
            child: c.busy
                ? CircularProgressIndicator(
                    value: c.progress > 0 ? c.progress : null,
                    strokeWidth: 2,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChartEditorField(
                label: text('editors.chart.title'),
                value: '${widget.host.project.meta['title']}',
                enabled: !c.busy,
                onCommit: (value) =>
                    widget.host.edit((p) => p.meta['title'] = value),
              ),
              const SizedBox(height: 16),
              ChartEditorField(
                key: ValueKey('summary:${c.owner}'),
                label: t('summary'),
                value: '${draft['summary'] ?? ''}',
                enabled: !c.busy,
                onCommit: (value) {
                  unawaited(c.update({'summary': value}));
                  return true;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('visibility:${draft['visibility']}'),
                initialValue: '${draft['visibility'] ?? 'public'}',
                decoration: InputDecoration(labelText: t('visibility')),
                items: [
                  for (final v in ['public', 'unlisted'])
                    DropdownMenuItem(value: v, child: Text(t(v))),
                ],
                onChanged: c.busy
                    ? null
                    : (value) => c.update({'visibility': value}),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(t('remixAllowed')),
                value: draft['remix'] != false,
                onChanged: c.busy
                    ? null
                    : (value) => c.update({'remix': value}),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t('audio')),
                subtitle: Text(widget.host.media?.ref.name ?? ''),
                trailing: IconButton(
                  onPressed: c.busy ? null : () => _choose('audio'),
                  tooltip: t('useAudio'),
                  icon: const Icon(Symbols.library_music_rounded),
                ),
              ),
              SizedBox(
                height: 180,
                child: cover is String
                    ? Image.file(
                        File(cover),
                        cacheWidth: 512,
                        fit: BoxFit.contain,
                      )
                    : draft['coverUrl'] is String
                    ? AppImage(
                        candidates: ['${draft['coverUrl']}'],
                        localized: false,
                      )
                    : c.published?['coverUrl'] is String
                    ? AppImage(
                        candidates: [
                          absoluteUrl('${c.published!['coverUrl']}'),
                        ],
                        localized: false,
                      )
                    : const Icon(Symbols.image_rounded, size: 64),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: c.busy ? null : _pickCover,
                    icon: const Icon(Symbols.upload_rounded),
                    label: Text(t('uploadCover')),
                  ),
                  OutlinedButton.icon(
                    onPressed: c.busy ? null : () => _choose('cover'),
                    icon: const Icon(Symbols.photo_library_rounded),
                    label: Text(t('selectCover')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        Visibility(
          visible: c.published?['publishedRevision'] != null,
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          child: TextButton(
            onPressed: c.busy ? null : c.withdraw,
            child: Text(t('unpublish')),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(text('common.actions.close')),
        ),
        OutlinedButton(
          onPressed: c.busy || !c.ready ? null : () => _save(false),
          child: Text(t('saveDraft')),
        ),
        FilledButton(
          onPressed: c.busy || !c.ready ? null : () => _save(true),
          child: Text(
            t(c.published?['publishedRevision'] == null ? 'publish' : 'update'),
          ),
        ),
      ],
    );
  }
}
