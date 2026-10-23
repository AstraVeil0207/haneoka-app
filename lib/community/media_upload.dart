import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../account/haneoka_account.dart';
import '../chart_editor/project.dart';
import '../core/net.dart';
import 'community_widgets.dart';

/// One account's cancellable upload transaction, shared by native chart media.
class CommunityMediaUpload {
  CommunityMediaUpload(this.owner, {required this.progress}) {
    _account.addListener(_changed);
  }
  final String owner;
  final void Function(double) progress;
  final _account = HaneokaAccount.instance;
  final _abort = Completer<void>();
  void _changed() {
    if (_account.user?['id'] != owner) close();
  }

  void check() {
    if (_abort.isCompleted || _account.user?['id'] != owner) {
      throw const AccountError('account_changed');
    }
  }

  Future<ChartMap> request(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    check();
    final result = await communityRequest(
      method,
      path,
      body: body,
      headers: headers,
    ).timeout(const Duration(seconds: 30));
    check();
    return result;
  }

  Future<ChartMap> send(
    String method,
    String path,
    File file,
    String type, {
    int start = 0,
    int? end,
    int completed = 0,
    int? total,
  }) async {
    check();
    final length = (end ?? await file.length()) - start,
        uri = Uri.parse(absoluteUrl(path));
    final request =
        http.AbortableStreamedRequest(method, uri, abortTrigger: _abort.future)
          ..contentLength = length
          ..followRedirects = false
          ..headers.addAll({
            'Content-Type': type,
            if (uri.origin == communityOrigin) ...{
              'Origin': communityOrigin,
              ..._account.authorization,
            },
          });
    final stopwatch = Stopwatch()..start();
    var sent = 0, last = 0;
    final responseFuture = netClient.send(request);
    unawaited(
      responseFuture.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    try {
      await for (final chunk in file.openRead(start, end)) {
        check();
        request.sink.add(chunk);
        sent += chunk.length;
        if (stopwatch.elapsedMilliseconds - last >= 100) {
          last = stopwatch.elapsedMilliseconds;
          progress((completed + sent) / (total ?? length));
        }
      }
      unawaited(request.sink.close());
      final response = await http.Response.fromStream(
        await responseFuture.timeout(const Duration(minutes: 3)),
      ).timeout(const Duration(minutes: 3));
      check();
      final result = response.bodyBytes.isEmpty
          ? <String, Object?>{}
          : chartMap(jsonDecode(utf8.decode(response.bodyBytes)));
      if (response.statusCode >= 300) {
        final error = result['error'];
        throw AccountError(error is Map ? '${error['code']}' : 'upload_failed');
      }
      progress((completed + length) / (total ?? length));
      return result;
    } catch (_) {
      if (!_abort.isCompleted) _abort.complete();
      rethrow;
    }
  }

  Future<ChartMap> cover(
    File file,
    String name,
    String type,
    String idempotencyKey, {
    ChartMap? previous,
    required Future<void> Function(ChartMap) persist,
  }) async {
    final length = await file.length();
    if (length == 0 ||
        length > 10 * 1024 * 1024 ||
        !const {'image/png', 'image/jpeg', 'image/webp'}.contains(type)) {
      throw const AccountError('cover_format');
    }
    var attachment = previous;
    if (attachment != null) {
      final response = await request(
        'GET',
        '/api/v1/community/attachments/${attachment['id']}',
      );
      attachment = chartMap(response['attachment']);
    }
    if (attachment == null || attachment['status'] == 'reserved') {
      final intent = await request(
        'POST',
        '/api/v1/community/uploads/intents',
        headers: {'Idempotency-Key': idempotencyKey},
        body: {'fileName': name, 'mediaType': type, 'size': length},
      );
      attachment = chartMap(intent['attachment']);
      await persist(attachment);
      final multipart = attachment['multipart'];
      if (multipart is! Map) {
        final response = await send(
          'PUT',
          '${attachment['uploadUrl']}',
          file,
          type,
        );
        if (response['attachment'] is Map) {
          attachment = chartMap(response['attachment']);
        }
      } else {
        final partSize = multipart['partSize'] as int,
            count = multipart['partCount'] as int,
            parts = <int, ChartMap>{};
        for (final row in chartRows(multipart['parts'] ?? const [])) {
          final number = row['partNumber'] as int;
          if (number >= 1 &&
              number <= count &&
              row['etag'] is String &&
              row['byteSize'] ==
                  math.min(partSize, length - (number - 1) * partSize)) {
            parts[number] = {'partNumber': number, 'etag': row['etag']};
          }
        }
        var completed = parts.keys.fold<int>(
          0,
          (sum, n) => sum + math.min(partSize, length - (n - 1) * partSize),
        );
        for (var n = 1; n <= count; n++) {
          if (parts.containsKey(n)) continue;
          final start = (n - 1) * partSize,
              end = math.min(length, n * partSize);
          final response = await send(
            'PUT',
            '${multipart['partUploadUrl']}'.replaceFirst('{partNumber}', '$n'),
            file,
            'application/octet-stream',
            start: start,
            end: end,
            completed: completed,
            total: length,
          );
          final part = chartMap(response['part']);
          parts[n] = {'partNumber': n, 'etag': part['etag']};
          completed += end - start;
        }
        final response = await request(
          'POST',
          '${multipart['completeUrl']}',
          body: {
            'parts': [for (final n in parts.keys.toList()..sort()) parts[n]],
          },
        );
        attachment = chartMap(response['attachment'] ?? response);
      }
      await persist(attachment);
    }
    ChartMap current = attachment;
    final processing = current['processing'];
    if (current['status'] == 'scanning' &&
        processing is Map &&
        const {'queued', 'failed'}.contains(processing['state'])) {
      final response = await request(
        'POST',
        '/api/v1/community/attachments/${current['id']}/retry',
      );
      current = chartMap(response['attachment'] ?? response);
    }
    for (var attempt = 0; attempt < 12; attempt++) {
      check();
      if (current['status'] == 'ready' &&
          current['moderationStatus'] == 'allow') {
        return current;
      }
      if (const {'rejected', 'deleted'}.contains(current['status'])) {
        throw const AccountError('cover_rejected');
      }
      final response = await request(
        'GET',
        '/api/v1/community/attachments/${current['id']}',
      );
      current = chartMap(response['attachment']);
      await persist(current);
      await Future.any<void>([
        Future<void>.delayed(const Duration(milliseconds: 1250)),
        _abort.future,
      ]);
    }
    throw const AccountError('media_not_ready');
  }

  void close() {
    _account.removeListener(_changed);
    if (!_abort.isCompleted) _abort.complete();
  }
}
