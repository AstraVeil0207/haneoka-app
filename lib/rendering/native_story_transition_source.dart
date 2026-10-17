import 'package:vega_plugin_haneoka/native_cubism.dart';
import 'package:vega_plugin_haneoka/render_profile.dart';

import '../core/api.dart';
import 'native_unity_source_archive.dart';

final class NativeStoryTransitionSource {
  NativeStoryTransitionSource._(this.gradient, this.texture, this.curve);
  final bool gradient;
  final Uri texture;
  final NativeCubismFadeCurve curve;

  static Future<NativeStoryTransitionSource> load({
    required HaneokaApi api,
    required StorySourceIdentity identity,
    required Map definition,
    required bool Function() current,
  }) async {
    final name = definition['name'] as String;
    final archive = await NativeUnitySourceArchive.load(
      api: api,
      identity: identity,
      sourcePath:
          definition['sourcePath'] as String? ??
          'Assets/AddressableResources/Adv/Transition/$name/$name.asset',
      current: current,
      decodeOffThread: true,
      retain: _retainTransitionRecord,
    );
    final data = archive.requireScript('RuleTransitionSettings')['data'] as Map;
    final uri = api.asset(definition['maskTexture'] as String);
    return NativeStoryTransitionSource._(
      data['_gradient'] == 1 || data['_gradient'] == true,
      uri.replace(
        queryParameters: {...uri.queryParameters, 'release': identity.release},
      ),
      NativeCubismFadeCurve(data['_easingCurve'] as Map),
    );
  }
}

bool _retainTransitionRecord(Map record) => record['type'] == 'MonoBehaviour';
