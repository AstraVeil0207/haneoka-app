/// A track the dock can show: what is playing and where it came from.
class Track {
  const Track({
    required this.id,
    required this.url,
    required this.title,
    this.subtitle = '',
    this.songKey,
    this.artwork,
  });
  final String id;
  final String url;
  final String title;
  final String subtitle;
  final String? songKey;
  final String? artwork;
}
