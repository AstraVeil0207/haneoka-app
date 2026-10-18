import '../catalog/visuals.dart';

String? episodeIdentityArtwork(
  Map episode,
  CatalogVisuals? visuals, {
  String? normalArtwork,
}) {
  final perspective = (episode['perspectiveCharacterId'] as num?)?.toInt() ?? 0;
  if (episode['isAnotherEpisode'] == true && perspective > 0) {
    final face = visuals?.characters[perspective]?['faceImage'];
    return face is String && face.isNotEmpty
        ? visuals!.api.asset(face).toString()
        : null;
  }
  return normalArtwork;
}
