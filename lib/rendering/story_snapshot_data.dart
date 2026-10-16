import 'package:vega_plugin_haneoka/render_profile.dart'
    show StorySourceIdentity;

Map<String, Object?> storySourceData(StorySourceIdentity value) => {
  'namespace': value.namespace,
  'revision': value.revision,
  'resourceScope': value.resourceScope,
  'document': value.document,
  'contentIdentity': value.contentIdentity,
};

void requireStorySourceData(Map data, StorySourceIdentity expected) {
  final value = storySourceData(expected);
  if (data.length != value.length ||
      !value.entries.every((entry) => data[entry.key] == entry.value)) {
    throw const FormatException('story_data_source_identity');
  }
}
