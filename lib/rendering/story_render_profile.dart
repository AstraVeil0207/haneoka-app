import 'package:haneoka_render_profile_flutter/haneoka_render_profile_flutter.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';

Future<StoryRenderProfileBinding> bindStoryRenderProfile(
  StorySourceIdentity chapter,
) async {
  final profile = await HaneokaProfileAssets.open();
  profile.requireCapability('haneoka-story-commands-v1');
  final source = profile.packetSource;
  return StoryRenderProfileBinding(
    chapterIdentity: chapter,
    profileId: '${profile.id}:${profile.version}',
    profileManifestSHA256: profile.manifestSHA256,
    packetSource: StorySourceIdentity(
      namespace: source['server'] as String,
      revision: source['releaseId'] as String,
      resourceScope: source['sourceId'] as String,
      document: 'profile:${profile.id}',
      contentIdentity: profile.manifestSHA256,
    ),
  );
}
