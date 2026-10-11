/// Skill descriptions as the website renders them (`src/lit/shared/skill-text.ts`):
/// the game's templates (`{effects[0].value/100:F1}`, `{0 < effects[0].time ? … : …}`)
/// filled from the effects of one skill level.
library;

typedef Effect = Map<String, Object?>;

Object? _field(Effect effect, List<String> keys) {
  final raw = effect['raw'] is Effect ? effect['raw'] as Effect : effect;
  for (final key in keys) {
    if (effect[key] != null) return effect[key];
    if (raw[key] != null) return raw[key];
  }
  return null;
}

num? _number(Object? value) =>
    value is num ? value : num.tryParse('${value ?? ''}'.trim());

/// The effects of [level], or of the highest level when none is asked for.
({int? level, List<Effect> effects}) skillLevelEffects(
  List<Effect> effects, [
  int? level,
]) {
  final levels = [
    for (final e in effects)
      if (_number(_field(e, ['level', '_level'])) case final l?) l.toInt(),
  ];
  if (levels.isEmpty) return (level: null, effects: _resolved(effects));
  final chosen = level ?? levels.reduce((a, b) => a > b ? a : b);
  return (
    level: chosen,
    effects: _resolved([
      for (final e in effects)
        if (_number(_field(e, ['level', '_level'])) == chosen) e,
    ]),
  );
}

List<Effect> _resolved(List<Effect> effects) => [
  for (final e in effects)
    {
      ...e,
      'value': _field(e, ['effectValue', '_effectValue']),
      'maxValue': _field(e, ['maxEffectValue', '_maxEffectValue']),
      'time': _field(e, ['activationTimeSecond', '_activationTimeSecond']),
      'limitCount': _field(e, ['effectLimitCount', '_effectLimitCount']),
      'executeLimitCount': _field(e, [
        'executeLimitCount',
        '_effectExecuteLimitCount',
      ]),
    },
];

Object? _at(Object? source, String path) {
  Object? value = source;
  for (final key
      in path
          .replaceAllMapped(RegExp(r'\[(\d+)]'), (m) => '.${m[1]}')
          .split('.')) {
    if (key.isEmpty) continue;
    final index = int.tryParse(key);
    value = value is List && index != null && index < value.length
        ? value[index]
        : value is Map
        ? value[key]
        : null;
  }
  return value;
}

final _valuePattern = RegExp(
  r'^(effects(?:\[\d+])(?:[.\w]|\[\d+])*)(?:([/*])(\d+(?:\.\d+)?))?(?::F(\d+))?$',
);
final _conditional = RegExp(
  r'^0\s*<\s*(effects(?:\[\d+])(?:[.\w]|\[\d+])*)\s*\?\s*(.*?)\s*:\s*(.*)$',
);

String? _value(
  String expression,
  Map<String, Object?> source,
  String Function(Object?) localize,
) {
  final match = _valuePattern.firstMatch(expression.trim());
  if (match == null) return null;
  final raw = _at(source, match[1]!);
  if (raw is num) {
    final operand = match[3] == null ? null : num.parse(match[3]!);
    final value = match[2] == '/'
        ? raw / operand!
        : match[2] == '*'
        ? raw * operand!
        : raw;
    if (!value.isFinite) return null;
    return match[4] == null
        ? _plain(value)
        : value.toStringAsFixed(int.parse(match[4]!));
  }
  if (raw is String) return raw;
  if (raw is List || raw is Map) {
    final text = localize(raw);
    return text.isEmpty ? null : text;
  }
  return null;
}

/// JavaScript's `String(number)`: no trailing `.0` on whole numbers.
String _plain(num value) =>
    value == value.truncate() ? '${value.truncate()}' : '$value';

String? _branch(
  String branch,
  Map<String, Object?> source,
  String Function(Object?) localize,
) {
  final trimmed = branch.trim();
  final quoted = RegExp(r'^"([^"]*)"$').firstMatch(trimmed);
  if (quoted != null) return quoted[1] ?? '';
  final out = StringBuffer();
  for (final part in trimmed.split(RegExp(r'\s*~\s*'))) {
    final literal = RegExp(r'^"([\s\S]*)"$').firstMatch(part);
    if (literal != null) {
      out.write(literal[1] ?? '');
      continue;
    }
    final value = _value(part, source, localize);
    if (value == null) return null;
    out.write(value);
  }
  return out.toString();
}

/// Fills [template] from [effects]; tokens it cannot resolve stay as written.
String skillDescription(
  String template,
  List<Effect> effects,
  String Function(Object?) localize,
) {
  final source = <String, Object?>{'effects': effects};
  final filled = template.replaceAllMapped(RegExp(r'\{([^{}]+)\}'), (m) {
    final body = m[1]!;
    final conditional = _conditional.firstMatch(body);
    if (conditional != null) {
      final condition = _at(source, conditional[1]!);
      if (condition is! num) return m[0]!;
      return _branch(
            condition > 0 ? conditional[2]! : conditional[3]!,
            source,
            localize,
          ) ??
          m[0]!;
    }
    return _value(body, source, localize) ?? m[0]!;
  });
  return filled
      .replaceAll(RegExp(r'<color=[^>]+>', caseSensitive: false), '')
      .replaceAll(RegExp(r'</color>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(r'\n', '\n')
      .trim();
}
