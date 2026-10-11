import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A website page the app opens in the system's in-app browser until it has
/// its own screen; `route` is the website's navigation route.
class WebPage {
  const WebPage(this.route, this.label, this.icon);
  final String route;
  final String label;
  final IconData icon;

  /// The canonical address: catalogue routes carry the release server.
  Uri url(String server, String locale) => Uri.parse(
    route.startsWith('/catalog/')
        ? 'https://haneoka.org/$server/$locale/${route.substring(9)}/'
        : 'https://haneoka.org/$locale$route/',
  );
}

class WebSection {
  const WebSection(this.id, this.label, this.icon, this.pages);
  final String id;
  final String label;
  final IconData icon;
  final List<WebPage> pages;
}

/// The website's other drawer sections (`src/config/navigation.ts`).
const webSections = <WebSection>[
  WebSection('stories', 'navigation.stories', Symbols.auto_stories_rounded, [
    WebPage(
      '/catalog/stories/event',
      'story.navigation.event',
      Symbols.local_activity_rounded,
    ),
    WebPage(
      '/catalog/stories/band',
      'story.navigation.band',
      Symbols.groups_rounded,
    ),
    WebPage(
      '/catalog/stories/link',
      'story.navigation.link',
      Symbols.diversity_1_rounded,
    ),
    WebPage(
      '/catalog/stories/birthday',
      'story.labels.birthdayStory',
      Symbols.cake_rounded,
    ),
    WebPage(
      '/catalog/stories/home',
      'story.navigation.home',
      Symbols.home_rounded,
    ),
    WebPage(
      '/catalog/stories/afterlive',
      'story.navigation.afterlive',
      Symbols.celebration_rounded,
    ),
    WebPage(
      '/catalog/stories/tutorial',
      'story.navigation.tutorial',
      Symbols.school_rounded,
    ),
  ]),
  WebSection('tools', 'navigation.tools', Symbols.build_rounded, [
    WebPage(
      '/catalog/events/tracker',
      'tools.eventTracker.title',
      Symbols.leaderboard_rounded,
    ),
    WebPage(
      '/calendar',
      'tools.calendar.title',
      Symbols.calendar_month_rounded,
    ),
    WebPage('/catalog/live2d', 'navigation.live2d', Symbols.animation_rounded),
    WebPage(
      '/catalog/spine',
      'navigation.spine',
      Symbols.accessibility_new_rounded,
    ),
    WebPage(
      '/catalog/assets',
      'navigation.assets',
      Symbols.folder_open_rounded,
    ),
    WebPage('/catalog/help', 'navigation.help', Symbols.help_rounded),
    WebPage(
      '/player-profile',
      'tools.playerProfile.title',
      Symbols.person_search_rounded,
    ),
    WebPage('/team-builder', 'tools.teamBuilder.title', Symbols.groups_rounded),
    WebPage(
      '/song-progress',
      'catalog.songProgress.title',
      Symbols.check_circle_rounded,
    ),
    WebPage('/stamp-maker', 'tools.stampMaker.title', Symbols.image_rounded),
    WebPage(
      '/chart-editor/create',
      'navigation.chartEditor',
      Symbols.edit_rounded,
    ),
  ]),
  WebSection('games', 'navigation.games', Symbols.sports_esports_rounded, [
    WebPage(
      '/sonolus',
      'catalog.sonolus.title',
      Symbols.sports_esports_rounded,
    ),
    WebPage(
      '/song-puzzle',
      'tools.songPuzzle.title',
      Symbols.extension_rounded,
    ),
    WebPage('/song-guess', 'catalog.songGuess.title', Symbols.help_rounded),
  ]),
  WebSection('community', 'navigation.community', Symbols.forum_rounded, [
    WebPage(
      '/community',
      'community.page.feedRecommended',
      Symbols.dynamic_feed_rounded,
    ),
    WebPage(
      '/community/latest',
      'community.page.feedLatest',
      Symbols.schedule_rounded,
    ),
    WebPage(
      '/community/playlists',
      'community.page.playlistPage.title',
      Symbols.queue_music_rounded,
    ),
    WebPage(
      '/community/forums',
      'community.page.forums',
      Symbols.forum_rounded,
    ),
    WebPage(
      '/community/songs-bestdori',
      'community.page.songsBestDori',
      Symbols.library_music_rounded,
    ),
    WebPage(
      '/community/sekai/songs',
      'community.page.sekai.title',
      Symbols.library_music_rounded,
    ),
  ]),
];
