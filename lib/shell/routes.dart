import 'package:flutter/material.dart';

import '../catalog/catalog_screen.dart';
import '../catalog/detail_screen.dart';
import '../catalog/profiles.dart';
import '../catalog/songs.dart';
import '../core/app_state.dart';
import '../home/home_screen.dart';
import '../ui/import_screen.dart';
import 'page.dart';
import 'settings_screen.dart';

/// The website's catalogue routes and the API resource each one browses.
const catalogRoutes = {
  '/catalog/songs': 'songs',
  '/catalog/events': 'events',
  '/catalog/characters': 'characters',
  '/catalog/member-cards': 'cards',
  '/catalog/support-cards': 'support-cards',
  '/catalog/skills': 'skills',
  '/catalog/comics': 'comics',
  '/catalog/gacha': 'gacha',
  '/catalog/login-campaigns': 'login-campaigns',
  '/catalog/missions': 'missions',
  '/catalog/passes': 'passes',
  '/catalog/tgw-card': 'tgw-card',
  '/catalog/shop': 'shop',
  '/catalog/exchange': 'exchange',
  '/catalog/stamps': 'stamps',
  '/catalog/stickers': 'stickers',
  '/catalog/backgrounds': 'backgrounds',
  '/catalog/items': 'items',
  '/catalog/band-items': 'band-items',
  '/catalog/real-lives': 'real-lives',
};

void openEntity(
  BuildContext context,
  CatalogProfile profile,
  Map<String, Object?> item,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => DetailScreen(
      profile: profile,
      id: '${firstOf(item, profile.id) ?? item['_key']}',
      summary: item,
    ),
  ),
);

/// The native screen for a website route, or null while it is being built.
Widget? screenFor(String route, {required ValueChanged<String> navigate}) {
  if (route == '/') return HomeScreen(onBrowse: navigate);
  if (route == '/settings') return const SettingsScreen();
  if (route == '/team-builder') return const ImportScreen();
  final resource = catalogRoutes[route];
  if (resource != null) {
    final profile = catalogProfiles.firstWhere((p) => p.resource == resource);
    void open(BuildContext context, Map<String, Object?> item) =>
        openEntity(context, profile, item);
    return profile.presentation == Presentation.song
        ? SongsScreen(onOpen: open)
        : CatalogScreen(profile: profile, onOpen: open);
  }
  return null;
}

/// A route whose native screen is still being written: its title bar and an
/// empty pane, never the website.
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => ShellPage(
    title: AppScope.of(context).text(label),
    body: const SizedBox.expand(),
  );
}
