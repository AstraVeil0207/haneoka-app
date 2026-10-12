/// Judgement conversion (effect types 12006 and 13005): registered
/// functions tried from the most recent (`engine/full/convert.ts`).
library;

import 'effects.dart' show endFrame, executeFrame;

const _just = 6;
const _convertToJust = 13005;

class _ConvertParam {
  _ConvertParam(this.key, this.maxCount, this.targets, this.to);
  final String key;
  int count = 0;
  final int maxCount;
  final List<int> targets;
  final int to;
}

class ConvertEffect {
  ConvertEffect(
    this.type,
    this.value,
    this.limitCount,
    this.targets,
    this.effectId,
  );
  final int type;
  final int value;
  final int limitCount;
  final List<int> targets;
  final int effectId;
}

class Conversion {
  Conversion(this._noJust);
  final Set<int> _noJust;
  final _order = <int>[];
  final _registered = <int>{};
  int _funcId = 0;
  final _idMap = <String, int>{};
  final _params = <int, _ConvertParam>{};
  final _limitFinished = <String, int>{};
  final _context = <int, List<int>>{};
  int converted = 0;

  int _register() {
    final k = ++_funcId;
    _registered.add(k);
    _order.insert(0, k);
    return k;
  }

  void _unregister(int id) {
    if (!_registered.remove(id)) {
      throw StateError('judgement convert function $id is not registered');
    }
    _order.remove(id);
  }

  int convert(int judgement, int judgementType, int timeMs) {
    for (var i = 0; i < _order.length; i++) {
      final key = _order[i];
      if (!_registered.contains(key)) continue;
      final out = _tryConvert(key, judgement, judgementType, timeMs);
      if (out != judgement) return out;
      if (!(i < _order.length && _order[i] == key)) i--;
    }
    return judgement;
  }

  int _tryConvert(int id, int cur, int judgementType, int timeMs) {
    final p = _params[id];
    if (p == null) return cur;
    if (p.to == -1 || !p.targets.contains(cur) || cur == p.to) return cur;
    if (p.to == _just && _noJust.contains(judgementType)) return cur;
    p.count++;
    if (p.maxCount > 0 && p.maxCount <= p.count) {
      _unregister(id);
      _idMap.remove(p.key);
      _params.remove(id);
      _limitFinished[p.key] = timeMs;
    }
    converted++;
    return p.to;
  }

  /// One applier update; returns the time the effect reached its limit when
  /// that is reported now.
  int? update(String key, int state, ConvertEffect effect) {
    final finished = _limitFinished.remove(key);
    if (finished != null) state = endFrame;
    if (state == endFrame) {
      final id = _idMap.remove(key);
      if (id != null) {
        _unregister(id);
        _params.remove(id);
      }
    } else if (state == executeFrame) {
      final targets = _context[effect.effectId] ??= effect.targets;
      final to = effect.type == _convertToJust
          ? _just
          : effect.value - 1 >= 0 && effect.value - 1 <= 5
          ? effect.value
          : -1;
      final id = _register();
      if (_idMap.containsKey(key)) {
        throw StateError('judgement convert state registered twice');
      }
      _idMap[key] = id;
      _params[id] = _ConvertParam(key, effect.limitCount, targets, to);
    }
    return finished;
  }
}
