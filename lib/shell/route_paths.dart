/// Public GBP routes follow the game name; saved Bestdori routes remain valid.
String canonicalAppPath(String path) {
  final parts = Uri.parse(path).pathSegments
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.length >= 2 && parts.first == 'community') {
    if (parts[1] == 'songs-bestdori' && parts.length <= 3) {
      parts.replaceRange(1, 2, ['gbp', 'songs']);
    } else if (parts[1] == 'stories-bestdori' && parts.length == 3) {
      parts.replaceRange(1, 2, ['gbp', 'stories']);
    }
  }
  return '/${parts.map(Uri.encodeComponent).join('/')}';
}
