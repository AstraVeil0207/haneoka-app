import 'dart:typed_data';

import '../account/haneoka_account.dart';
import '../core/account_resource.dart';
import '../community/community_widgets.dart';
import 'audio.dart';
import 'controller.dart';
import 'formats.dart';
import 'project.dart';
import 'storage.dart';

Future<void> openCommunityEditor(
  ChartEditorController host,
  Map<String, String> query,
) async {
  final account = HaneokaAccount.instance;
  await account.load();
  final epoch = AccountResources.instance.epoch,
      owner = '${account.user?['id'] ?? ''}',
      id = query['communityId']!,
      remix = query['remix'] == '1';
  ChartMap? item, document;
  await host.importResource(() async {
    final uri = Uri(
      path: '/api/v1/community/charts/$id/project',
      queryParameters: {
        if (!remix) 'draft': '1',
        if (query['revision'] != null) 'revision': query['revision']!,
      },
    );
    final response = objectOf(
      await account
          .request('GET', uri.toString())
          .timeout(const Duration(seconds: 30)),
    );
    item = chartMap(response['chart']);
    document = chartMap(response['document']);
    if (remix && item!['remix'] != true && item!['canEdit'] != true) {
      throw const AccountError('remix_unavailable');
    }
    final project = ChartProject(chartMap(document!['project']))
      ..requireValid();
    final url = Uri.parse(absoluteUrl('${document!['audioUrl']}'));
    final lease = await AccountResources.instance.acquire(
      url,
      maximumBytes: 64 * 1024 * 1024,
    );
    NativeChartAudio audio;
    try {
      audio = await decodeChartAudio(
        host.store,
        lease.file,
        name: '${item!['title']}.audio',
        type: lease.mediaType,
      );
    } finally {
      await lease.release();
    }
    if (epoch != AccountResources.instance.epoch) {
      await audio.close();
      throw const AccountError('account_changed');
    }
    return (
      chart: ChartImport(
        'project',
        project,
        project.validate().where((i) => i.warning).toList(),
      ),
      audio: audio,
      source: null,
    );
  });
  if (host.error != null || item == null || document == null) return;
  final row = item!, value = document!;
  final draft = <String, Object?>{
    ...portableChartPublication(value),
    'audioSha': host.media?.ref.sha,
    if (row['canEdit'] == true && !remix) ...{
      'id': id,
      'version': row['version'],
      'revision': value['revision'],
      'ownerId': owner,
      'audio': value['audio'],
      'cover': value['cover'],
    } else
      'upstreamId': id,
  };
  if ((row['canEdit'] != true || remix) &&
      draft['cover'] == null &&
      '${value['coverUrl'] ?? ''}'.isNotEmpty) {
    final lease = await AccountResources.instance.acquire(
      Uri.parse(absoluteUrl('${value['coverUrl']}')),
      maximumBytes: 10 * 1024 * 1024,
    );
    try {
      final bytes = await lease.file.readAsBytes(),
          type = lease.mediaType ?? 'image/png',
          extension = type == 'image/jpeg'
              ? 'jpg'
              : type == 'image/webp'
              ? 'webp'
              : 'png';
      final cover = await host.store.saveCover(
        host.id,
        Uint8List.fromList(bytes),
        extension,
      );
      draft.addAll({
        'coverFile': cover.path,
        'coverName': 'cover.$extension',
        'coverType': type,
        'coverKey': chartUuid(),
      });
    } finally {
      await lease.release();
    }
  }
  if (epoch != AccountResources.instance.epoch) {
    throw const AccountError('account_changed');
  }
  await host.store.savePublication(host.id, owner, draft);
}
