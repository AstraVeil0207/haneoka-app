import '../catalog/browse.dart';
import '../catalog/visuals.dart';
import '../core/i18n.dart';

List<FacetSpec> modelMetadataFacets(List<Entry> models, SiteText t) {
  String value(Entry model, String key) {
    if (key == 'preview') {
      final preview = model['preview'] as Map?;
      return preview?['url'] != null || preview?['runtime'] != null ? 'yes' : 'no';
    }
    final v = model[key];
    return v is bool ? (v ? 'yes' : 'no') : '${v ?? ''}';
  }
  return [
    for (final key in ['quality', 'costumeId', 'subCharacter', 'preview'])
      if (models.map((row) => value(row, key)).where((v) => v.isNotEmpty).toSet().length >= 2)
        FacetSpec(key: key,
          label: t(key == 'preview' ? 'common.actions.preview' : 'media.models.labels.$key'),
          values: (row) => [if (value(row, key).isNotEmpty) value(row, key)],
          option: (v) => FacetOption(v == 'yes' || v == 'no' ? t('common.states.$v') : v)),
  ];
}
