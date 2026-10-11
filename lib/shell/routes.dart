import 'package:flutter/material.dart';

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
  if (route == '/catalog') return CatalogHubScreen(navigate: navigate);
  if (route == '/announcements') return const AnnouncementsScreen();
  if (route == '/calendar') return const CalendarScreen();
  if (route == '/join') return const JoinScreen();
  if (route == '/catalog/song-meta') return const SongMetaScreen();
  if (route == '/catalog/skills') return const SkillsScreen();
  if (route == '/catalog/studio') return const StudioScreen();
  if (route == '/catalog/events/tracker') return const EventTrackerScreen();
  if (route == '/player-profile') return const PlayerProfileScreen();
  if (route == '/team-builder') return const ImportScreen();
  if (route.startsWith('/catalog/stories/')) {
    final mode = route.substring('/catalog/stories/'.length);
    if (storyModes.contains(mode)) {
      return StoriesScreen(key: ValueKey(mode), mode: mode);
    }
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
