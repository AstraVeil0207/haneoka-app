import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../catalog/cross_server.dart';
import '../catalog/profiles.dart';
import '../core/app_state.dart';
import '../stories/stories.dart';
import 'page.dart';
import 'routes.dart';

/// The website's entity kinds (`RESOURCE_KINDS`) and the API resource each
/// browses, for addresses like `/intl/ja/events/1/`.
const _kindResources = {
  'songs': 'songs',
  'events': 'events',
  'characters': 'characters',
  'member-cards': 'cards',
  'support-cards': 'support-cards',
  'skills': 'skills',
  'comics': 'comics',
  'gacha': 'gacha',
  'login-campaigns': 'login-campaigns',
  'missions': 'missions',
  'passes': 'passes',
  'tgw-card': 'tgw-card',
  'shop': 'shop',
  'exchange': 'exchange',
  'stamps': 'stamps',
  'stickers': 'stickers',
  'backgrounds': 'backgrounds',
  'items': 'items',
  'band-items': 'band-items',
  'real-lives': 'real-lives',
};

const _servers = {'jp', 'intl', 'jp-test', 'intl-test'};
const _locales = {'ja', 'en', 'zh-TW', 'zh-CN', 'ko'};

/// Opens a haneoka.org address inside the app: an entity's page, or the
/// collection or tool the address names. Addresses on other sites open in
/// the browser. Returns false when there is nothing to open.
Future<bool> openLink(
  BuildContext context,
  String href, {
  ValueChanged<String>? navigate,
}) async {
  navigate ??= ShellScope.of(context)?.navigate;
  final uri = Uri.tryParse(href);
  if (uri == null) return false;
  if (uri.path.isEmpty && uri.hasFragment) return false;
  if (uri.hasScheme && !const {'http', 'https'}.contains(uri.scheme)) {
    if (!const {'mailto', 'tel', 'sonolus'}.contains(uri.scheme)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  if (uri.host.isNotEmpty && uri.host != 'haneoka.org') {
    return launchUrl(
      uri.hasScheme ? uri : uri.replace(scheme: 'https'),
      mode: LaunchMode.externalApplication,
    );
  }
  final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  final server = parts.isNotEmpty && _servers.contains(parts.first)
      ? parts.removeAt(0)
      : null;
  if (parts.isNotEmpty && _locales.contains(parts.first)) parts.removeAt(0);
  if (parts.isEmpty) {
    navigate?.call('/');
    return navigate != null;
  }
  if (parts.length >= 3 &&
      parts.first == 'catalog' &&
      _kindResources.containsKey(parts[1]) &&
      !(parts[1] == 'events' && parts[2] == 'tracker')) {
    parts.removeAt(0);
  }
  if (parts.join('/') == 'events/tracker') {
    navigate?.call('/catalog/events/tracker');
    return navigate != null;
  }
  // Only the entity parameter opens a detail; search/sort/band parameters remain collection state.
  if (parts.length == 2 &&
      parts.first == 'catalog' &&
      _kindResources.containsKey(parts[1])) {
    final parameter = switch (parts[1]) {
      'member-cards' => 'card',
      'support-cards' => 'snap',
      'characters' => 'character',
      'comics' => 'comic',
      'stamps' => 'stamp',
      'stickers' => 'sticker',
      'backgrounds' => 'background',
      'songs' => 'song',
      'events' ||
      'real-lives' ||
      'gacha' ||
      'login-campaigns' ||
      'shop' ||
      'exchange' ||
      'passes' => 'entry',
      _ => 'item',
    };
    final id = uri.queryParameters[parameter];
    if (id != null && id.isNotEmpty) {
      parts
        ..removeAt(0)
        ..add(id);
    }
  }
  final story = parts.first == 'stories' && parts.length > 1
      ? parts[1]
      : parts.first == 'catalog' && parts.elementAtOrNull(1) == 'stories'
      ? uri.queryParameters['story'] ?? uri.queryParameters['episode']
      : null;
  if (story != null && story.isNotEmpty) {
    final state = AppScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StoryReaderScreen(
          episode: {'storyKey': story},
          api: state.apiFor(server ?? state.server),
        ),
      ),
    );
    return true;
  }
  final resource = _kindResources[parts.first];
  if (resource != null) {
    final profile = catalogProfiles
        .where((p) => p.resource == resource)
        .firstOrNull;
    if (profile == null) return false;
    if (parts.length >= 2) {
      final selected = AppScope.maybeOf(context)?.server;
      openEntity(context, profile, {
        profile.id.first: int.tryParse(parts[1]) ?? parts[1],
        '_key': parts[1],
        if (server != null && server != selected) serverKey: server,
      });
      return true;
    }
    navigate?.call('/catalog/${parts.first}');
    return navigate != null;
  }
  // A playlist is addressed by query: `/community/playlists?playlist=<id>`.
  final playlist = uri.queryParameters['playlist'];
  if (parts.join('/') == 'community/playlists' && playlist != null) {
    parts.add(playlist);
  }
  // A GBP or Project Sekai song: `/community/songs-bestdori/detail/?song=1`.
  final song = uri.queryParameters['song'];
  if (const {
        'community/songs-bestdori/detail',
        'community/sekai/songs/detail',
      }.contains(parts.join('/')) &&
      song != null) {
    parts
      ..removeLast()
      ..add(song);
  }
  final route = '/${parts.join('/')}';
  if (navigate != null) {
    navigate(route);
    return true;
  }
  return false;
}
