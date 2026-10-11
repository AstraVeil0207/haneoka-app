import 'package:flutter/material.dart';

import '../about/about_screen.dart';
import '../catalog/browse.dart';
import '../catalog/missions.dart';
import '../catalog/tgw_card.dart';
import '../catalog/catalog_screen.dart';
import '../catalog/detail_screen.dart';
import '../catalog/hub_screen.dart';
import '../catalog/profiles.dart';
import '../catalog/skills.dart';
import '../catalog/song_meta.dart';
import '../catalog/songs.dart';
import '../catalog/studio.dart';
import '../core/app_state.dart';
import '../home/announcements.dart';
import '../home/calendar.dart';
import '../home/home_screen.dart';
import '../records/player.dart';
import '../stories/stories.dart';
import '../records/tracker.dart';
import '../home/join.dart';
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
  Map<String, Object?> item, {
  List<Map<String, Object?>>? siblings,
}) {
  final list = siblings ?? BrowseSiblings.of(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DetailScreen(
        profile: profile,
        id: '${firstOf(item, profile.id) ?? item['_key']}',
        summary: item,
        siblings: list,
      ),
    ),
  );
}

/// The native screen for a website route, or null while it is being built.
Widget? screenFor(String route, {required ValueChanged<String> navigate}) {
  if (route == '/') return HomeScreen(onBrowse: navigate);
  if (route == '/settings') return const SettingsScreen();
  if (route == '/catalog') return CatalogHubScreen(navigate: navigate);
  if (route == '/announcements') return const AnnouncementsScreen();
  if (route == '/calendar') return const CalendarScreen();
  if (route == '/join') return const JoinScreen();
  if (route == '/catalog/song-meta') return const SongMetaScreen();
  if (route == '/catalog/skills') return const SkillsScreen();
  if (route == '/catalog/missions') return const MissionsScreen();
  if (route == '/catalog/tgw-card') return const TgwCardScreen();
  if (route == '/catalog/studio') return const StudioScreen();
  if (route == '/catalog/events/tracker') return const EventTrackerScreen();
  if (route == '/player-profile') return const PlayerProfileScreen();
  if (route == '/account') return const AccountsScreen();
  if (route == '/about') return const AboutScreen();
  if (route.startsWith('/catalog/stories/')) {
    final mode = route.substring('/catalog/stories/'.length);
    if (storyModes.contains(mode)) {
      return StoriesScreen(key: ValueKey(mode), mode: mode);
    }
  }
  final slash = route.lastIndexOf('/');
  final parent = slash > '/catalog'.length
      ? catalogRoutes[route.substring(0, slash)]
      : null;
  if (parent case final resource?) {
    return DetailScreen(
      key: ValueKey(route),
      profile: catalogProfiles.firstWhere((p) => p.resource == resource),
      id: route.substring(slash + 1),
      summary: const {},
    );
  }
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
