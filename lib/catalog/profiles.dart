import 'package:flutter/material.dart';

/// How a catalogue resource is shown: the same profiles the website uses.
class CatalogProfile {
  const CatalogProfile({
    required this.resource,
    required this.label,
    required this.icon,
    this.id = const ['id'],
    this.title = const ['title', 'name'],
    this.image = const ['image', 'thumbnail'],
    this.detail = const [],
    this.document,
    this.layout = TileLayout.square,
    this.newestFirst = true,
  });

  /// The API resource name.
  final String resource;

  /// The website's message path for its name.
  final String label;
  final IconData icon;
  final List<String> id, title, image, detail;

  /// The key holding the collection inside the document, when not top level.
  final String? document;
  final TileLayout layout;
  final bool newestFirst;
}

enum TileLayout { square, portrait, wide }

/// The catalogue, in the website's drawer order.
const catalogProfiles = <CatalogProfile>[
  CatalogProfile(
    resource: 'songs', label: 'navigation.songs', icon: Icons.library_music,
    id: ['musicId', 'id'], title: ['musicTitle', 'title'], image: ['jacketThumbUrl', 'jacketUrl', 'image'],
    detail: ['bandName', 'composer', 'lyricist', 'arranger', 'publishedAt'],
  ),
  CatalogProfile(
    resource: 'events', label: 'navigation.events', icon: Icons.event,
    document: 'entries', detail: ['kind', 'startAt', 'endAt'], layout: TileLayout.wide,
  ),
  CatalogProfile(
    resource: 'characters', label: 'navigation.characters', icon: Icons.group,
    id: ['characterId', 'id'], title: ['characterName', 'name'], image: ['faceImage', 'thumbnailImage', 'image'],
    detail: ['bandPart', 'birthday', 'height', 'school', 'schoolClass', 'constellation', 'favoriteFood', 'hobby'],
    newestFirst: false,
  ),
  CatalogProfile(
    resource: 'cards', label: 'navigation.memberCards', icon: Icons.style,
    id: ['cardId', 'id'], title: ['prefix', 'cardName', 'name'], image: ['images.thumbnail', 'thumbnail', 'image'],
    detail: ['rarity', 'cardType', 'releasedAt'],
  ),
  CatalogProfile(
    resource: 'support-cards', label: 'navigation.supportCards', icon: Icons.collections,
    id: ['supportCardId', 'id'], title: ['prefix', 'cardName', 'name'], image: ['images.thumbnail', 'thumbnail', 'image'],
    detail: ['rarity', 'cardType', 'releasedAt'], layout: TileLayout.wide,
  ),
  CatalogProfile(resource: 'skills', label: 'catalog.cards.fields.skills', icon: Icons.bolt, title: ['name', 'skillName', 'title']),
  CatalogProfile(
    resource: 'comics', label: 'navigation.comics', icon: Icons.menu_book,
    id: ['comicId', 'id'], detail: ['subTitle', 'publicStartAt'],
  ),
  CatalogProfile(resource: 'gacha', label: 'navigation.gacha', icon: Icons.redeem, document: 'entries', detail: ['category', 'startAt', 'endAt'], layout: TileLayout.wide),
  CatalogProfile(resource: 'login-campaigns', label: 'navigation.loginCampaigns', icon: Icons.event_available, document: 'entries', layout: TileLayout.wide),
  CatalogProfile(resource: 'missions', label: 'navigation.systemNavMissions', icon: Icons.fact_check, document: 'entries', layout: TileLayout.wide),
  CatalogProfile(resource: 'passes', label: 'navigation.systemNavPasses', icon: Icons.workspace_premium, document: 'entries', layout: TileLayout.wide),
  CatalogProfile(resource: 'tgw-card', label: 'catalog.tgwCard.card', icon: Icons.credit_card, document: 'entries', layout: TileLayout.wide),
  CatalogProfile(resource: 'shop', label: 'navigation.shop', icon: Icons.storefront, document: 'entries', layout: TileLayout.wide),
  CatalogProfile(resource: 'exchange', label: 'navigation.exchange', icon: Icons.swap_horiz, document: 'entries', layout: TileLayout.wide),
  CatalogProfile(resource: 'stamps', label: 'navigation.stamps', icon: Icons.emoji_emotions, id: ['stampId', 'id'], detail: ['releasedAt']),
  CatalogProfile(resource: 'stickers', label: 'navigation.stickers', icon: Icons.sticky_note_2, id: ['stickerId', 'id'], document: 'entries', detail: ['description']),
  CatalogProfile(resource: 'backgrounds', label: 'navigation.backgrounds', icon: Icons.wallpaper, id: ['backgroundId', 'id'], document: 'entries', layout: TileLayout.wide),
  CatalogProfile(resource: 'items', label: 'navigation.items', icon: Icons.inventory_2, id: ['itemId', 'id'], document: 'items', newestFirst: false),
  CatalogProfile(resource: 'band-items', label: 'navigation.bandItems', icon: Icons.piano, id: ['bandItemId', 'itemId', 'id'], document: 'items', newestFirst: false),
  CatalogProfile(resource: 'real-lives', label: 'navigation.realLives', icon: Icons.festival, document: 'entries', layout: TileLayout.wide),
];

/// Reads a dotted path from a record.
Object? readPath(Object? value, String path) {
  Object? node = value;
  for (final part in path.split('.')) {
    node = node is Map ? node[part] : null;
  }
  return node;
}

Object? firstOf(Map<String, Object?> record, List<String> paths) {
  for (final path in paths) {
    final value = readPath(record, path);
    if (value != null && value != '' && !(value is List && value.isEmpty)) return value;
  }
  return null;
}
