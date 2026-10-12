/// Exact Top-K over leader → four members → snap assignment
/// (`team-builder/engine/search.ts`).
///
/// Every slot contributes power p, skill weight g and event bonus e
/// additively; an objective maps (P, G, E) monotonically to its key, so
/// optimistic sums give valid bounds. Survivors are ranked by an interval
/// around the key and only those that can still enter the Top-K are
/// evaluated exactly.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'master.dart';
import 'num.dart';
import 'power.dart';

class Totals {
  const Totals({
    required this.power,
    required this.skill,
    this.skillLow = 0,
    this.bonus = 0,
  });
  final double power;

  /// Optimistic skill weight (upper end of the key).
  final double skill;

  /// Pessimistic skill weight (lower end of the key).
  final double skillLow;
  final double bonus;

  Totals copyWith({double? power, double? skill, double? skillLow}) => Totals(
    power: power ?? this.power,
    skill: skill ?? this.skill,
    skillLow: skillLow ?? this.skillLow,
    bonus: bonus,
  );
}

class Team {
  Team(this.members, this.snaps);

  /// Member indices; slot 0 is the leader.
  final List<int> members;

  /// Snap index per slot, -1 for an empty slot.
  final List<int> snaps;
}

class Exact<D> {
  Exact(this.key, this.detail);
  final double key;
  final D detail;
}

typedef AssignmentBound = double Function(
  Totals totals,
  List<int> assigned,
  int from,
);

class JointTarget {
  JointTarget(this.bonus, this.product);
  final double bonus;
  final double product;
}

class ObjectiveAdapter<D> {
  ObjectiveAdapter({
    required this.skill,
    required this.memberBonus,
    required this.snapBonus,
    this.snapDominance,
    this.preserveSnapOptions = false,
    required this.bound,
    this.assignmentBound,
    this.productBase,
    this.hard = false,
    this.jointTargets,
    this.preferSnap,
    this.leafBound,
    this.memberBound,
    this.preferMember,
    required this.interval,
    required this.exact,
    this.evaluate,
  });

  /// Optional exact evaluator that may stop (null) only after proving the
  /// team cannot enter the retained Top-K.
  final Exact<D>? Function(
    Team team,
    int power,
    List<int> slotPowers,
    ({double key, bool pruneEqual}) cutoff,
  )?
  evaluate;

  /// [pessimistic, optimistic] skill weight of a member with snap (-1 empty).
  final (double, double) Function(int member, int snap) skill;

  /// Additive event bonus of a member and a snap (BP, 10000 = 100 %).
  final int Function(int member) memberBonus;
  final int Function(int snap) snapBonus;

  /// Additional monotone dimensions required before discarding a dominated snap.
  final List<double> Function(int member, int snap)? snapDominance;

  /// Equality-constrained objectives cannot replace a snap with a stronger one.
  final bool preserveSnapOptions;

  /// Upper bound of the key for optimistic totals.
  final double Function(Totals totals) bound;

  /// Tighter bounds after the members and each snap prefix are fixed.
  final AssignmentBound Function(List<int> members, List<List<int>> options)?
  assignmentBound;

  /// When set, `bound` depends on power and skill only through
  /// power × (productBase + skill).
  final double? productBase;

  /// The bounds are loose for this objective (life-draining plays).
  final bool hard;
  final double Function(List<int> members, Totals totals, int left)?
  memberBound;
  final double Function(int member)? preferMember;

  /// Joint bonus/product requirements a team must meet to reach a key.
  final List<JointTarget> Function(double limit)? jointTargets;

  /// Snap ordering hint: higher first within a slot.
  final double Function(int member, int snap)? preferSnap;

  /// Optional tighter upper bound for a complete team.
  final double Function(Team team, Totals totals)? leafBound;

  /// Interval containing the exact key of a complete team with exact power.
  final (double, double) Function(Team team, Totals totals) interval;
  final Exact<D> Function(Team team, int power, List<int> slotPowers) exact;
}

class Constraints {
  const Constraints({
    this.requiredMembers = const [],
    this.excludedMembers = const [],
    this.requiredSnaps = const [],
    this.excludedSnaps = const [],
    this.leader,
    this.bindings = const {},
    this.noSnaps = false,
    this.minBonus,
    this.maxBonus,
  });
  final List<int> requiredMembers;
  final List<int> excludedMembers;
  final List<int> requiredSnaps;
  final List<int> excludedSnaps;
  final int? leader;

  /// member index → snap index (-1 keeps the slot empty).
  final Map<int, int> bindings;
  final bool noSnaps;

  /// Minimum event bonus (BP).
  final double? minBonus;
  final double? maxBonus;
}

class SearchHit<D> {
  SearchHit(
    this.team,
    this.power,
    this.slotPowers,
    this.totals,
    this.key,
    this.detail,
  );
  final Team team;
  final int power;
  final List<int> slotPowers;
  final Totals totals;
  final double key;
  final D detail;
}

class SearchStats {
  SearchStats();
  factory SearchStats.fromJson(Map<String, Object?> json) => SearchStats()
    ..leaders = intOf(json['leaders'])
    ..memberNodes = intOf(json['memberNodes'])
    ..snapNodes = intOf(json['snapNodes'])
    ..candidates = intOf(json['candidates'])
    ..exact = intOf(json['exact'])
    ..elapsedMs = numOf(json['elapsedMs']);
  int leaders = 0;
  int memberNodes = 0;
  int snapNodes = 0;
  int candidates = 0;
  int exact = 0;
  double elapsedMs = 0;
  Map<String, Object?> toJson() => {
    'leaders': leaders,
    'memberNodes': memberNodes,
    'snapNodes': snapNodes,
    'candidates': candidates,
    'exact': exact,
    'elapsedMs': elapsedMs,
  };
  void add(SearchStats other) {
    leaders += other.leaders;
    memberNodes += other.memberNodes;
    snapNodes += other.snapNodes;
    candidates += other.candidates;
    exact += other.exact;
    elapsedMs += other.elapsedMs;
  }
}

class SearchOutput<D> {
  SearchOutput(this.hits, this.proven, this.bound, this.stats);
  final List<SearchHit<D>> hits;
  final bool proven;

  /// Upper bound of any unexplored team when not proven.
  final double? bound;
  final SearchStats stats;
}

class _Candidate {
  _Candidate(
    this.setKey,
    this.team,
    this.power,
    this.slotPowers,
    this.totals,
    this.low,
    this.high,
  );
  final String setKey;
  final Team team;
  final int power;
  final List<int> slotPowers;
  final Totals totals;
  final double low;
  final double high;
}

// Scratch of maxAssignment, grown on demand.
var _scratchSize = 0;
var _scratchU = Float64List(0),
    _scratchV = Float64List(0),
    _scratchMinv = Float64List(0);
var _scratchP = Int32List(0), _scratchWay = Int32List(0);
var _scratchUsed = Uint8List(0);
final _smallColumns = Int32List(25);
final _smallValues = Float64List(25);
final _smallUsed = Uint8List(4096);

double _smallAssignment(List<Float64List> weights, int columns) {
  final n = weights.length;
  for (var r = 0; r < n; r++) {
    final row = weights[r];
    final base = r * 5;
    for (var k = 0; k < n; k++) {
      _smallColumns[base + k] = -1;
      _smallValues[base + k] = -inf;
    }
    for (var c = 0; c < columns; c++) {
      final value = row[c];
      if (value <= _smallValues[base + n - 1]) continue;
      var k = n - 1;
      while (k > 0 && _smallValues[base + k - 1] < value) {
        _smallValues[base + k] = _smallValues[base + k - 1];
        _smallColumns[base + k] = _smallColumns[base + k - 1];
        k--;
      }
      _smallValues[base + k] = value;
      _smallColumns[base + k] = c;
    }
  }
  var best = -inf;
  void search(int r, double total) {
    if (r == n) {
      if (total > best) best = total;
      return;
    }
    final base = r * 5;
    for (var k = 0; k < n; k++) {
      final c = _smallColumns[base + k];
      if (c < 0 || _smallUsed[c] != 0) continue;
      _smallUsed[c] = 1;
      search(r + 1, total + _smallValues[base + k]);
      _smallUsed[c] = 0;
    }
  }

  search(0, 0);
  return best;
}

/// Maximum-weight assignment of rows to distinct columns (rows ≤ columns),
/// Hungarian algorithm.
double maxAssignment(
  List<Float64List> weights,
  int columns, [
  Int32List? rowColumn,
]) {
  final n = weights.length;
  if (rowColumn == null && n <= 4 && columns <= _smallUsed.length) {
    return _smallAssignment(weights, columns);
  }
  const big = double.maxFinite / 4;
  final size = math.max(n, columns) + 1;
  if (size > _scratchSize) {
    _scratchSize = size * 2;
    _scratchU = Float64List(_scratchSize);
    _scratchV = Float64List(_scratchSize);
    _scratchP = Int32List(_scratchSize);
    _scratchWay = Int32List(_scratchSize);
    _scratchMinv = Float64List(_scratchSize);
    _scratchUsed = Uint8List(_scratchSize);
  }
  final u = _scratchU,
      v = _scratchV,
      p = _scratchP,
      way = _scratchWay,
      minv = _scratchMinv,
      used = _scratchUsed;
  u.fillRange(0, n + 1, 0);
  v.fillRange(0, columns + 1, 0);
  p.fillRange(0, columns + 1, 0);
  way.fillRange(0, columns + 1, 0);
  for (var i = 1; i <= n; i++) {
    p[0] = i;
    var j0 = 0;
    minv.fillRange(0, columns + 1, big);
    used.fillRange(0, columns + 1, 0);
    do {
      used[j0] = 1;
      final i0 = p[j0];
      var delta = big;
      var j1 = 0;
      final row = weights[i0 - 1];
      for (var j = 1; j <= columns; j++) {
        if (used[j] == 0) {
          final cur = -row[j - 1] - u[i0] - v[j];
          if (cur < minv[j]) {
            minv[j] = cur;
            way[j] = j0;
          }
          if (minv[j] < delta) {
            delta = minv[j];
            j1 = j;
          }
        }
      }
      for (var j = 0; j <= columns; j++) {
        if (used[j] != 0) {
          u[p[j]] += delta;
          v[j] -= delta;
        } else {
          minv[j] -= delta;
        }
      }
      j0 = j1;
    } while (p[j0] != 0);
    do {
      final j1 = way[j0];
      p[j0] = p[j1];
      j0 = j1;
    } while (j0 != 0);
  }
  var total = 0.0;
  for (var j = 1; j <= columns; j++) {
    if (p[j] != 0) {
      total += weights[p[j] - 1][j - 1];
      if (rowColumn != null) rowColumn[p[j] - 1] = j - 1;
    }
  }
  return total;
}

/// Keeps the K best distinct member sets by a lower key.
class _Frontier {
  _Frontier(this.k);
  final int k;
  final _best = <String, double>{};
  final _sorted = <double>[];

  void offer(String setKey, double value) {
    final previous = _best[setKey];
    if (previous != null && previous >= value) return;
    if (previous == null && _sorted.length >= k && value <= threshold) return;
    _best[setKey] = value;
    if (previous != null) _sorted.removeAt(_sorted.indexOf(previous));
    var index = _sorted.length;
    while (index > 0 && _sorted[index - 1] < value) {
      index--;
    }
    _sorted.insert(index, value);
    if (_sorted.length > k) {
      final removed = _sorted.removeLast();
      for (final entry in _best.entries) {
        if (entry.value == removed) {
          _best.remove(entry.key);
          break;
        }
      }
    }
  }

  double get threshold => _sorted.length >= k ? _sorted[k - 1] : -inf;
}

class _Tables {
  _Tables(int rows, int maxColumns)
    : columnSnap = Int32List(maxColumns),
      power = _rows(rows, maxColumns),
      weight = _rows(rows, maxColumns),
      bonus = _rows(rows, maxColumns),
      blended = _rows(rows, maxColumns),
      joint = _rows(rows, maxColumns);
  static List<Float64List> _rows(int rows, int columns) => [
    for (var r = 0; r < rows; r++) Float64List(columns),
  ];
  int count = 0;
  int columns = 0;
  final Int32List columnSnap;
  final List<Float64List> power;
  final List<Float64List> weight;
  final List<Float64List> bonus;
  final List<Float64List> blended;
  final List<Float64List> joint;
}

SearchOutput<D> searchTeams<D>({
  required EngineMaster master,
  required PlayerState player,
  required List<MemberState> members,
  required List<SnapState> snaps,
  required MusicView? music,
  required ObjectiveAdapter<D> objective,
  Constraints constraints = const Constraints(),
  required int k,
  double? timeLimitMs,
  List<Team>? seeds,
  ({int index, int count})? shard,
  double? floor,
  bool floorExclusive = false,
  bool Function(List<int> members)? owns,
  void Function(List<SearchHit<D>> hits)? onCandidate,
  int Function(MemberState member)? memberPowerPercent,
  int Function(SnapState snap)? snapPowerPercent,
  bool disableSnapDominance = false,
  void Function(int done, int total)? progress,
  bool Function()? cancelled,
}) {
  final clock = Stopwatch()..start();
  double now() => clock.elapsedMicroseconds / 1000;
  k = math.max(1, k);
  final n = members.length, s = snaps.length;
  final stats = SearchStats();
  final excludedMember = constraints.excludedMembers.toSet();
  final excludedSnap = constraints.excludedSnaps.toSet();
  final bases = [
    for (final member in members)
      slotBase(
        master,
        player,
        member,
        music,
        memberPowerPercent?.call(member) ?? 0,
      ),
  ];
  final snapEvent = [
    for (final snap in snaps) snapPowerPercent?.call(snap) ?? 0,
  ];
  // Snap power per (member, snap); column s is the empty slot.
  final width = s + 1;
  final snapPower = Float64List(n * width);
  final skill = Float64List(n * width);
  final skillLow = Float64List(n * width);
  final allowedSnaps = <int>[
    for (var j = 0; j < s; j++)
      if (!excludedSnap.contains(j) && !constraints.noSnaps) j,
  ];
  for (var i = 0; i < n; i++) {
    for (final j in allowedSnaps) {
      snapPower[i * width + j] = snapPoints(
        master,
        bases[i],
        members[i],
        snaps[j],
        snapEvent[j],
      ).toDouble();
      final (low, high) = objective.skill(i, j);
      skillLow[i * width + j] = low;
      skill[i * width + j] = high;
    }
    snapPower[i * width + s] = 0;
    final (low, high) = objective.skill(i, -1);
    skillLow[i * width + s] = low;
    skill[i * width + s] = high;
  }
  final memberBonus = [for (var i = 0; i < n; i++) objective.memberBonus(i)];
  final snapBonus = [for (var j = 0; j < s; j++) objective.snapBonus(j)];
  final anySnapBonus = snapBonus.any((value) => value != 0);
  // Usable snaps with a bonus, largest first.
  final bonusOrder = [
    for (final j in allowedSnaps)
      if (snapBonus[j] > 0) j,
  ]..sort((a, b) => snapBonus[b] - snapBonus[a]);
  final snapBonusTop5 = ([
    for (final j in allowedSnaps)
      if (snapBonus[j] > 0) snapBonus[j],
  ]..sort((a, b) => b - a)).take(5).fold(0, (sum, value) => sum + value);
  // Per member: the best snap contribution ignoring snap distinctness.
  ({double power, double weight, double bonus}) bestSnap(int i) {
    final bound = constraints.bindings[i];
    final options = bound != null ? [bound] : [...allowedSnaps, -1];
    var power = 0.0, weight = 0.0, bonus = 0.0;
    for (final j in options) {
      final column = j < 0 ? s : j;
      power = math.max(power, snapPower[i * width + column]);
      weight = math.max(weight, skill[i * width + column]);
      bonus = math.max(bonus, j < 0 ? 0 : snapBonus[j].toDouble());
    }
    return (power: power, weight: weight, bonus: bonus);
  }

  final required = constraints.requiredMembers.toSet()
    ..addAll(constraints.bindings.keys);
  final requiredSnaps = constraints.requiredSnaps.toSet();
  for (final snap in constraints.bindings.values) {
    if (snap >= 0) requiredSnaps.remove(snap);
  }
  final best = [for (var i = 0; i < n; i++) bestSnap(i)];
  // A slot never needs a snap that five other usable snaps dominate for its member.
  final boundElsewhere = {
    for (final j in constraints.bindings.values)
      if (j >= 0) j,
  };
  final snapOptions = <List<int>>[
    for (var i = 0; i < n; i++)
      () {
        final bound = constraints.bindings[i];
        if (bound != null) return [bound];
        final list = [
          ...allowedSnaps.where((j) => !boundElsewhere.contains(j)),
          -1,
        ];
        List<double> value(int j) {
          final column = j < 0 ? s : j;
          return [
            snapPower[i * width + column],
            skill[i * width + column],
            skillLow[i * width + column],
            j < 0 ? 0 : snapBonus[j].toDouble(),
            ...?objective.snapDominance?.call(i, j),
          ];
        }

        final values = [for (final j in list) value(j)];
        final kept = disableSnapDominance || objective.preserveSnapOptions
            ? list
            : [
                for (final (a, j) in list.indexed)
                  if (j < 0 ||
                      requiredSnaps.contains(j) ||
                      () {
                        var dominated = 0;
                        for (var b = 0; b < list.length && dominated < 5; b++) {
                          if (b == a || list[b] < 0) continue;
                          final x = values[a], y = values[b];
                          var all = true, equal = true;
                          for (var d = 0; d < x.length; d++) {
                            if (y[d] < x[d]) all = false;
                            if (y[d] != x[d]) equal = false;
                          }
                          if (all && (!equal || b < a)) dominated++;
                        }
                        return dominated < 5;
                      }())
                    j,
              ];
        final prefer = objective.preferSnap;
        return _stableSorted(kept, (a, b) {
          final p = prefer != null ? prefer(i, b) - prefer(i, a) : 0.0;
          if (p != 0) return p.sign.toInt();
          return (snapPower[i * width + (b < 0 ? s : b)] -
                  snapPower[i * width + (a < 0 ? s : a)])
              .sign
              .toInt();
        });
      }(),
  ];
  final profiles = <int, LeaderProfile>{};
  LeaderProfile profile(int leader) =>
      profiles[leader] ??= leaderProfile(master, members[leader]);

  final maxColumns = s + 5;
  final pools = [
    for (var from = 0; from < 5; from++) _Tables(5 - from, maxColumns),
  ];
  final columnOf = Int32List(s);
  final columnStamp = Int32List(s);
  var stamp = 0;
  final frontier = _Frontier(k);
  final hits = <SearchHit<D>>[];
  final retainedKeys = <String, double>{};
  final floorValue = floor ?? -inf;
  var timedOut = false;
  var unexploredBound = -inf;
  final deadline = timeLimitMs ?? inf;
  bool pastDeadline() => now() > deadline || (cancelled?.call() ?? false);

  String setKeyOf(Team team) =>
      ([for (final i in team.members) members[i].key]..sort()).join('|');

  // Equality is prunable only after k distinct legal teams have been evaluated exactly.
  bool cannotImprove(double upper) =>
      (floorExclusive && upper <= floorValue) ||
      hits.length >= k && upper <= hits[k - 1].key;
  void retain(_Candidate candidate, [Exact<D>? evaluated]) {
    if (evaluated == null && hits.length >= k && pastDeadline()) {
      timedOut = true;
      unexploredBound = math.max(unexploredBound, candidate.high);
      return;
    }
    if (cannotImprove(candidate.high)) return;
    final existing = hits.indexWhere(
      (hit) => setKeyOf(hit.team) == candidate.setKey,
    );
    if (existing >= 0 && hits[existing].key >= candidate.high) return;
    final local = math.max(
      hits.length >= k ? hits[k - 1].key : -inf,
      existing >= 0 ? hits[existing].key : -inf,
    );
    final exact =
        evaluated ??
        (objective.evaluate != null
            ? objective.evaluate!(
                candidate.team,
                candidate.power,
                candidate.slotPowers,
                (
                  key: math.max(local, floorValue),
                  pruneEqual:
                      floorExclusive || local >= floorValue && local.isFinite,
                ),
              )
            : objective.exact(
                candidate.team,
                candidate.power,
                candidate.slotPowers,
              ));
    if (exact == null) return;
    if (evaluated == null) stats.exact++;
    frontier.offer(candidate.setKey, exact.key);
    if (existing >= 0 && hits[existing].key >= exact.key) return;
    if (existing >= 0) hits.removeAt(existing);
    final hit = SearchHit(
      candidate.team,
      candidate.power,
      candidate.slotPowers,
      candidate.totals,
      exact.key,
      exact.detail,
    );
    var index = hits.length;
    while (index > 0 && hits[index - 1].key < hit.key) {
      index--;
    }
    hits.insert(index, hit);
    retainedKeys[candidate.setKey] = exact.key;
    if (hits.length > k) retainedKeys.remove(setKeyOf(hits.removeLast().team));
    onCandidate?.call(List.unmodifiable(hits));
  }

  final leaders = [
    for (var i = 0; i < n; i++)
      if (!excludedMember.contains(i) &&
          (constraints.leader == null || constraints.leader == i))
        i,
  ];
  // Leader order: strongest optimistic slot first, so the threshold rises early.
  double memberScore(int i) => bases[i].fixedPoints + best[i].power;
  int preference(int a, int b) => objective.preferMember == null
      ? 0
      : (objective.preferMember!(b) - objective.preferMember!(a)).sign.toInt();
  final orderedLeaders = _stableSorted(
    leaders,
    (a, b) => preference(a, b) != 0
        ? preference(a, b)
        : (memberScore(b) - memberScore(a)).sign.toInt(),
  );
  // Interleaved over the strength order, so every shard holds a balanced mix.
  final myLeaders = shard != null && shard.count > 1
      ? [
          for (final (position, leader) in orderedLeaders.indexed)
            if (position % shard.count == shard.index) leader,
        ]
      : orderedLeaders;
  if (myLeaders.isEmpty) {
    stats.elapsedMs = now();
    return SearchOutput([], true, null, stats);
  }

  bool seedValid(Team seed) {
    final team = seed.members;
    if (team.length != 5 || team.toSet().length != 5) return false;
    if (team.any(excludedMember.contains)) return false;
    if (constraints.leader != null && team[0] != constraints.leader) {
      return false;
    }
    if (team.map((i) => members[i].card.characterId).toSet().length != 5) {
      return false;
    }
    for (final i in required) {
      if (!team.contains(i)) return false;
    }
    final used = seed.snaps.where((j) => j >= 0).toList();
    if (used.toSet().length != used.length) return false;
    if (constraints.noSnaps && used.isNotEmpty) return false;
    for (final j in used) {
      if (excludedSnap.contains(j)) return false;
    }
    for (final j in requiredSnaps) {
      if (!used.contains(j)) return false;
    }
    for (var slot = 0; slot < 5; slot++) {
      final bound = constraints.bindings[team[slot]];
      if (bound != null && seed.snaps[slot] != bound) return false;
      if (bound == null &&
          seed.snaps[slot] >= 0 &&
          boundElsewhere.contains(seed.snaps[slot])) {
        return false;
      }
    }
    return true;
  }

  final seen = <String>{};
  void evaluateSeed(Team seed) {
    final id = '${seed.members.join(',')}|${seed.snaps.join(',')}';
    if (!seen.add(id)) return;
    final team = seed.members;
    final setKey = setKeyOf(seed);
    final percents = leaderPercents(
      master,
      profile(team[0]),
      [for (final i in team) members[i]],
      0,
      music,
    );
    final slotPowers = [
      for (final (slot, i) in team.indexed)
        bases[i].fixedPoints +
            leaderPoints(bases[i], percents[slot]) +
            snapPower[i * width + (seed.snaps[slot] < 0 ? s : seed.snaps[slot])]
                .toInt(),
    ];
    final power = slotPowers.fold(0, (sum, value) => sum + value);
    var weight = 0.0, weightLow = 0.0, bonus = 0.0;
    for (final (slot, i) in team.indexed) {
      final snap = seed.snaps[slot];
      weight += skill[i * width + (snap < 0 ? s : snap)];
      weightLow += skillLow[i * width + (snap < 0 ? s : snap)];
      bonus += memberBonus[i] + (snap < 0 ? 0 : snapBonus[snap]);
    }
    if (constraints.minBonus != null && bonus < constraints.minBonus!) return;
    if (constraints.maxBonus != null && bonus > constraints.maxBonus!) return;
    final evaluated = objective.exact(seed, power, slotPowers);
    stats.exact++;
    frontier.offer(setKey, evaluated.key);
    retain(
      _Candidate(
        setKey,
        Team([...team], [...seed.snaps]),
        power,
        slotPowers,
        Totals(
          power: power.toDouble(),
          skill: weight,
          skillLow: weightLow,
          bonus: bonus,
        ),
        evaluated.key,
        evaluated.key,
      ),
      evaluated,
    );
  }

  for (final seed in seeds ?? const <Team>[]) {
    if (pastDeadline()) break;
    if (seedValid(seed)) evaluateSeed(seed);
  }

  /// Snap assignment for one member set; records every assignment that can still rank.
  void assignSnaps(int leader, List<int> others) {
    final team = [leader, ...others];
    final setKey = ([for (final i in team) members[i].key]..sort()).join('|');
    bool cannotImproveSet(double upper) =>
        cannotImprove(upper) || (retainedKeys[setKey] ?? -inf) >= upper;
    final lead = profile(leader);
    List<int>? exactLead;
    if (!lead.simple) {
      final percents = leaderPercents(
        master,
        lead,
        [for (final i in team) members[i]],
        0,
        music,
      );
      exactLead = [
        for (final (slot, i) in team.indexed)
          leaderPoints(bases[i], percents[slot]),
      ];
    }
    final basePower = [
      for (final (slot, i) in team.indexed)
        bases[i].fixedPoints +
            (exactLead != null
                ? exactLead[slot]
                : leaderPoints(
                    bases[i],
                    leaderPercentBound(master, lead, members[i]),
                  )),
    ];
    final options = [for (final i in team) snapOptions[i]];
    final used = Uint8List(s);
    for (final entry in constraints.bindings.entries) {
      if (entry.value >= 0 && !team.contains(entry.key)) used[entry.value] = 1;
    }
    final assignment = List<int>.filled(5, -1);
    final tightenedBound = objective.assignmentBound?.call(team, options);
    double bound(Totals totals, [int from = 0]) => tightenedBound != null
        ? tightenedBound(totals, assignment, from)
        : objective.bound(totals);
    final maxPower = [for (final i in team) best[i].power];
    final maxWeight = [for (final i in team) best[i].weight];
    final maxBonus = [for (final i in team) best[i].bonus];
    Float64List suffixOf(List<double> values) {
      final table = Float64List(values.length + 1);
      for (var k = values.length - 1; k >= 0; k--) {
        table[k] = table[k + 1] + values[k];
      }
      return table;
    }

    final powerSuffix = suffixOf(maxPower);
    final weightSuffix = suffixOf(maxWeight);
    final bonusSuffix = suffixOf(maxBonus);
    final memberTotalBonus = team.fold(0, (sum, i) => sum + memberBonus[i]);
    int requiredLeft() => requiredSnaps.isEmpty
        ? 0
        : requiredSnaps.where((j) => used[j] == 0).length;
    var setLow = -inf;
    double limit() =>
        math.max(math.max(frontier.threshold, setLow), floorValue);
    const none = -1e15;

    /// Remaining slots × (unused snaps + one empty column per slot).
    _Tables tables(int from) {
      final t = pools[from];
      stamp++;
      var count = 0;
      for (var slot = from; slot < 5; slot++) {
        for (final j in options[slot]) {
          if (j >= 0 && used[j] == 0 && columnStamp[j] != stamp) {
            columnStamp[j] = stamp;
            columnOf[j] = count;
            t.columnSnap[count++] = j;
          }
        }
      }
      final rows = 5 - from;
      final columns = count + rows;
      t.count = count;
      t.columns = columns;
      for (var r = 0; r < rows; r++) {
        final slot = from + r;
        final i = team[slot];
        final p = t.power[r], w = t.weight[r], b = t.bonus[r];
        p.fillRange(0, columns, none);
        w.fillRange(0, columns, none);
        b.fillRange(0, columns, none);
        for (final j in options[slot]) {
          if (j >= 0 && used[j] != 0) continue;
          final column = j < 0 ? s : j;
          final vp = snapPower[i * width + column],
              vw = skill[i * width + column],
              vb = j < 0 ? 0.0 : snapBonus[j].toDouble();
          if (j < 0) {
            for (var empty = count; empty < columns; empty++) {
              p[empty] = vp;
              w[empty] = vw;
              b[empty] = vb;
            }
          } else {
            final at = columnOf[j];
            p[at] = vp;
            w[at] = vw;
            b[at] = vb;
          }
        }
      }
      return t;
    }

    List<Float64List> blend(_Tables t, double l) {
      for (var r = 0; r < t.power.length; r++) {
        final out = t.blended[r], row = t.power[r], w = t.weight[r];
        for (var c = 0; c < t.columns; c++) {
          out[c] = row[c] <= none / 2 ? none : l * row[c] + w[c] / l;
        }
      }
      return t.blended;
    }

    bool jointFeasible(
      _Tables t,
      double x,
      double y,
      double bonus,
      double P,
      double S,
      double B,
      double need,
      double product,
    ) {
      if (bonus + B < need) return false;
      if ((x + P) * (y + S) < product) return false;
      if (bonus >= need) return true;
      final lambda = math.sqrt((y + S) / math.max(1e-9, x + P));
      final K = 2 * math.sqrt(product) - lambda * x - y / lambda;
      final linear = blend(t, lambda);
      var spread = 0.0;
      for (var r = 0; r < linear.length; r++) {
        for (final value in linear[r]) {
          if (value > none / 2) spread = math.max(spread, value);
        }
      }
      for (final factor in const [0.25, 1.0, 4.0]) {
        final mu = factor * spread / math.max(1, need - bonus);
        for (var r = 0; r < linear.length; r++) {
          final out = t.joint[r], row = linear[r], b = t.bonus[r];
          for (var c = 0; c < t.columns; c++) {
            out[c] = row[c] <= none / 2 ? none : row[c] + mu * b[c];
          }
        }
        if (maxAssignment(t.joint, t.columns) < K + mu * (need - bonus)) {
          return false;
        }
      }
      return true;
    }

    double remainingBound(int from, double power, double weight, double bonus) {
      final t = tables(from);
      final P = maxAssignment(t.power, t.columns);
      final S = maxAssignment(t.weight, t.columns);
      if (P <= none / 2 || S <= none / 2) return -inf;
      final B = anySnapBonus ? maxAssignment(t.bonus, t.columns) : 0.0;
      final base = objective.productBase;
      if (anySnapBonus && objective.jointTargets != null && base != null) {
        final targets = objective.jointTargets!(limit());
        if (!targets.any(
          (target) => jointFeasible(
            t,
            power,
            base + weight,
            bonus,
            P,
            S,
            B,
            target.bonus,
            target.product,
          ),
        )) {
          return -inf;
        }
      }
      if (base == null) {
        return bound(
          Totals(power: power + P, skill: weight + S, bonus: bonus + B),
          from,
        );
      }
      final x = power, y = base + weight;
      var product = (x + P) * (y + S);
      if (bound(
            Totals(
              power: product / (y + S),
              skill: weight + S,
              bonus: bonus + B,
            ),
            from,
          ) <
          limit()) {
        return -inf;
      }
      final lambda = math.sqrt((y + S) / math.max(1e-9, x + P));
      for (final scale in const [1.0, 1.02, 1 / 1.02]) {
        final l = lambda * scale;
        final M = maxAssignment(blend(t, l), t.columns);
        product = math.min(product, math.pow(l * x + y / l + M, 2) / 4);
      }
      return bound(
        Totals(power: product / (y + S), skill: weight + S, bonus: bonus + B),
        from,
      );
    }

    final baseTotal = basePower.fold(0, (sum, value) => sum + value).toDouble();
    if (bound(
          Totals(
            power: baseTotal + powerSuffix[0],
            skill: weightSuffix[0],
            bonus: memberTotalBonus + bonusSuffix[0],
          ),
        ) <
        limit()) {
      return;
    }
    if (constraints.maxBonus != null &&
        memberTotalBonus > constraints.maxBonus!) {
      return;
    }
    if (constraints.minBonus != null &&
        memberTotalBonus +
                (anySnapBonus
                    ? maxAssignment(tables(0).bonus, tables(0).columns)
                    : 0) <
            constraints.minBonus!) {
      return;
    }
    final upper = remainingBound(0, baseTotal, 0, memberTotalBonus.toDouble());
    if (upper < limit() || cannotImproveSet(upper)) return;
    List<int> slotPowersOf(List<int> picks) => [
      for (final (index, i) in team.indexed)
        basePower[index] +
            snapPower[i * width + (picks[index] < 0 ? s : picks[index])]
                .toInt(),
    ];
    // Incumbent: the assignment maximizing the linearized key.
    if (objective.productBase != null && requiredSnaps.isEmpty) {
      final picks = List<int>.filled(5, -1);
      final t = tables(0);
      final P = maxAssignment(t.power, t.columns);
      final S = maxAssignment(t.weight, t.columns);
      final x = baseTotal;
      final l = math.sqrt((objective.productBase! + S) / math.max(1e-9, x + P));
      final rowColumn = Int32List(5);
      if (maxAssignment(blend(t, l), t.columns, rowColumn) > none / 2) {
        final snapOf = t.columnSnap.sublist(0, t.count);
        for (var row = 0; row < 5; row++) {
          final column = rowColumn[row];
          picks[row] = column < snapOf.length ? snapOf[column] : -1;
        }
        var power = x, weight = 0.0, weightLow = 0.0;
        var bonus = memberTotalBonus.toDouble();
        for (final (slot, i) in team.indexed) {
          final j = picks[slot];
          final column = j < 0 ? s : j;
          power += snapPower[i * width + column];
          weight += skill[i * width + column];
          weightLow += skillLow[i * width + column];
          bonus += j < 0 ? 0 : snapBonus[j];
        }
        final totals = Totals(
          power: power,
          skill: weight,
          skillLow: weightLow,
          bonus: bonus,
        );
        final fits =
            (constraints.minBonus == null || bonus >= constraints.minBonus!) &&
            (constraints.maxBonus == null || bonus <= constraints.maxBonus!);
        if (fits) {
          final (low, high) = objective.interval(Team(team, picks), totals);
          if (high >= limit() && !cannotImproveSet(high)) {
            frontier.offer(setKey, low);
            setLow = math.max(setLow, low);
            stats.candidates++;
            retain(
              _Candidate(
                setKey,
                Team([...team], [...picks]),
                power.toInt(),
                slotPowersOf(picks),
                totals,
                low,
                high,
              ),
            );
          }
        }
      }
    }
    double unusedBonusTop(int count) {
      var total = 0.0;
      for (var k = 0; k < bonusOrder.length && count > 0; k++) {
        final j = bonusOrder[k];
        if (used[j] != 0) continue;
        total += snapBonus[j];
        count--;
      }
      return total;
    }

    void walk(
      int slot,
      double power,
      double weight,
      double weightLow,
      double bonus,
    ) {
      if (!timedOut && (++stats.snapNodes & 1023) == 0 && pastDeadline()) {
        timedOut = true;
      }
      if (timedOut) {
        unexploredBound = math.max(
          unexploredBound,
          bound(
            Totals(
              power: power + powerSuffix[slot],
              skill: weight + weightSuffix[slot],
              bonus: bonus + bonusSuffix[slot],
            ),
          ),
        );
        return;
      }
      if (slot == 5) {
        if (requiredLeft() > 0) return;
        final totals = Totals(
          power: power,
          skill: weight,
          skillLow: weightLow,
          bonus: bonus,
        );
        if (constraints.minBonus != null && bonus < constraints.minBonus!) {
          return;
        }
        if (constraints.maxBonus != null && bonus > constraints.maxBonus!) {
          return;
        }
        if (bound(totals, 5) < limit()) return;
        final candidateTeam = Team(team, assignment);
        if (objective.leafBound != null &&
            objective.leafBound!(candidateTeam, totals) < limit()) {
          return;
        }
        final (low, high) = objective.interval(candidateTeam, totals);
        if (high < limit() || cannotImproveSet(high)) return;
        frontier.offer(setKey, low);
        setLow = math.max(setLow, low);
        stats.candidates++;
        retain(
          _Candidate(
            setKey,
            Team([...team], [...assignment]),
            power.toInt(),
            slotPowersOf(assignment),
            totals,
            low,
            high,
          ),
        );
        return;
      }
      final optimistic = bound(
        Totals(
          power: power + powerSuffix[slot],
          skill: weight + weightSuffix[slot],
          bonus: bonus + math.min(bonusSuffix[slot], unusedBonusTop(5 - slot)),
        ),
        slot,
      );
      if (optimistic < limit() || cannotImproveSet(optimistic)) return;
      if (slot > 0 &&
          slot < 4 &&
          remainingBound(slot, power, weight, bonus) < limit()) {
        return;
      }
      // One slot left: only options that can still reach the limit are walked.
      List<int>? lastOptions;
      if (slot == 4 && objective.productBase != null) {
        final i = team[4];
        final bar = limit();
        final keep = <int>[];
        for (final j in options[4]) {
          if (j >= 0 && used[j] != 0) continue;
          final column = j < 0 ? s : j;
          final value = bound(
            Totals(
              power: power + snapPower[i * width + column],
              skill: weight + skill[i * width + column],
              bonus: bonus + (j < 0 ? 0 : snapBonus[j]),
            ),
          );
          if (value >= bar) keep.add(j);
        }
        if (keep.isEmpty) return;
        lastOptions = keep;
      }
      if (5 - slot < requiredLeft()) return;
      final i = team[slot];
      for (final j in lastOptions ?? options[slot]) {
        if (j >= 0 && used[j] != 0) continue;
        final column = j < 0 ? s : j;
        if (j >= 0) used[j] = 1;
        assignment[slot] = j;
        walk(
          slot + 1,
          power + snapPower[i * width + column],
          weight + skill[i * width + column],
          weightLow + skillLow[i * width + column],
          bonus + (j < 0 ? 0 : snapBonus[j]),
        );
        if (j >= 0) used[j] = 0;
      }
      assignment[slot] = -1;
    }

    walk(0, baseTotal, 0, 0, memberTotalBonus.toDouble());
  }

  for (final (leaderIndex, leader) in myLeaders.indexed) {
    progress?.call(leaderIndex, myLeaders.length);
    if (pastDeadline()) timedOut = true;
    stats.leaders++;
    final leaderSkill = profile(leader);
    final leaderCharacter = members[leader].card.characterId;
    if (required.any(
      (i) => i != leader && members[i].card.characterId == leaderCharacter,
    )) {
      continue;
    }
    // Leader points per member: exact when the profile is simple, else an upper bound.
    final leadPoints = Float64List(n);
    for (var i = 0; i < n; i++) {
      leadPoints[i] = leaderPoints(
        bases[i],
        leaderPercentBound(master, leaderSkill, members[i]),
      ).toDouble();
    }
    double slotPower(int i) => bases[i].fixedPoints + leadPoints[i];
    // Characters other than the leader's, each with its eligible members.
    final groups = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      if (i == leader || excludedMember.contains(i)) continue;
      final character = members[i].card.characterId;
      if (character == leaderCharacter) continue;
      (groups[character] ??= []).add(i);
    }
    final forced = <List<int>>[];
    final free = <List<int>>[];
    var conflict = false;
    for (final list in groups.values) {
      final must = list.where(required.contains).toList();
      if (must.length > 1) {
        conflict = true;
        break;
      }
      final ordered = _stableSorted(
        must.isNotEmpty ? must : list,
        (a, b) => preference(a, b) != 0
            ? preference(a, b)
            : (slotPower(b) + best[b].power - (slotPower(a) + best[a].power))
                  .sign
                  .toInt(),
      );
      (must.isNotEmpty ? forced : free).add(ordered);
    }
    if (conflict || groups.isEmpty || forced.length > 4) continue;
    final freeSorted = _stableSorted(
      free,
      (a, b) => preference(a[0], b[0]) != 0
          ? preference(a[0], b[0])
          : (slotPower(b[0]) +
                    best[b[0]].power -
                    (slotPower(a[0]) + best[a[0]].power))
                .sign
                .toInt(),
    );
    final characters = [...forced, ...freeSorted];
    final forcedCount = forced.length;
    final charPower = [
      for (final list in characters)
        maxOf(list.map((i) => slotPower(i) + best[i].power)),
    ];
    final charSkill = [
      for (final list in characters) maxOf(list.map((i) => best[i].weight)),
    ];
    final charBonus = [
      for (final list in characters)
        maxOf(list.map((i) => memberBonus[i] + best[i].bonus)),
    ];
    final charMemberBonus = [
      for (final list in characters) maxOf(list.map((i) => memberBonus[i])),
    ];
    // Suffix top-4 sums: tops[from][c] is the sum of the c largest values from index `from` on.
    List<Float64List> suffixTops(List<double> values) {
      final tops = List<Float64List>.filled(values.length + 1, Float64List(5));
      var top = <double>[-inf, -inf, -inf, -inf];
      for (var index = values.length - 1; index >= 0; index--) {
        top = ([
          ...top,
          values[index],
        ]..sort((a, b) => b.compareTo(a))).take(4).toList();
        final row = Float64List(5);
        for (var c = 1; c <= 4; c++) {
          row[c] = row[c - 1] + (top[c - 1] == -inf ? 0 : top[c - 1]);
        }
        tops[index] = row;
      }
      return tops;
    }

    final topsPower = suffixTops(charPower);
    final topsSkill = suffixTops(charSkill);
    final topsBonus = suffixTops(charBonus);
    final topsMemberBonus = suffixTops(charMemberBonus);
    double topSum(List<Float64List> table, int from, int count) => count <= 0
        ? 0
        : table[math.min(from, table.length - 1)][math.min(count, 4)];
    double memberOnlyBound(double memberPart, int index, int left) =>
        memberPart + topSum(topsMemberBonus, index, left) + snapBonusTop5;
    if (characters.length < 4) continue;
    final leaderPower = slotPower(leader) + best[leader].power;
    final leaderWeight = best[leader].weight;
    final leaderBonus = memberBonus[leader] + best[leader].bonus;
    double memberSetBound(List<int> chosen, Totals totals, int left) {
      final plain = objective.bound(totals);
      if (objective.memberBound == null ||
          plain < math.max(frontier.threshold, floorValue)) {
        return plain;
      }
      return math.min(plain, objective.memberBound!(chosen, totals, left));
    }

    final leaderBound = memberSetBound(
      [leader],
      Totals(
        power: leaderPower + topSum(topsPower, 0, 4),
        skill: leaderWeight + topSum(topsSkill, 0, 4),
        bonus: math.min(
          leaderBonus + topSum(topsBonus, 0, 4),
          memberOnlyBound(memberBonus[leader].toDouble(), 0, 4),
        ),
      ),
      4,
    );
    if (leaderBound < math.max(frontier.threshold, floorValue) ||
        cannotImprove(leaderBound)) {
      continue;
    }
    if (timedOut) {
      unexploredBound = math.max(unexploredBound, leaderBound);
      continue;
    }
    if (constraints.minBonus != null &&
        leaderBonus + topSum(topsBonus, 0, 4) < constraints.minBonus!) {
      continue;
    }

    final chosen = <int>[];
    double memberOptimisticSnapBonus(List<int> list) =>
        best[leader].bonus + list.fold(0.0, (sum, i) => sum + best[i].bonus);
    void visit(
      int index,
      double power,
      double weight,
      double bonus,
      double memberPart,
    ) {
      final left = 4 - chosen.length;
      if (timedOut) {
        unexploredBound = math.max(
          unexploredBound,
          objective.bound(
            Totals(
              power: power + topSum(topsPower, index, left),
              skill: weight + topSum(topsSkill, index, left),
              bonus: bonus + topSum(topsBonus, index, left),
            ),
          ),
        );
        return;
      }
      stats.memberNodes++;
      if (left == 0) {
        if (owns == null || owns([leader, ...chosen])) {
          assignSnaps(leader, [...chosen]);
        }
        return;
      }
      if (characters.length - index < left) return;
      if (index < forcedCount) {
        for (final i in characters[index]) {
          chosen.add(i);
          visit(
            index + 1,
            power + slotPower(i) + best[i].power,
            weight + best[i].weight,
            bonus + memberBonus[i] + best[i].bonus,
            memberPart + memberBonus[i],
          );
          chosen.removeLast();
        }
        return;
      }
      final nodeBound = memberSetBound(
        [leader, ...chosen],
        Totals(
          power: power + topSum(topsPower, index, left),
          skill: weight + topSum(topsSkill, index, left),
          bonus: math.min(
            bonus + topSum(topsBonus, index, left),
            memberOnlyBound(memberPart, index, left),
          ),
        ),
        left,
      );
      if (nodeBound < math.max(frontier.threshold, floorValue) ||
          cannotImprove(nodeBound)) {
        return;
      }
      if (constraints.minBonus != null &&
          bonus + topSum(topsBonus, index, left) < constraints.minBonus!) {
        return;
      }
      if (constraints.maxBonus != null &&
          bonus - memberOptimisticSnapBonus(chosen) > constraints.maxBonus!) {
        return;
      }
      if (pastDeadline()) {
        timedOut = true;
        unexploredBound = math.max(unexploredBound, nodeBound);
        return;
      }
      for (final i in characters[index]) {
        chosen.add(i);
        visit(
          index + 1,
          power + slotPower(i) + best[i].power,
          weight + best[i].weight,
          bonus + memberBonus[i] + best[i].bonus,
          memberPart + memberBonus[i],
        );
        chosen.removeLast();
      }
      visit(index + 1, power, weight, bonus, memberPart);
    }

    visit(
      0,
      leaderPower,
      leaderWeight,
      leaderBonus,
      memberBonus[leader].toDouble(),
    );
  }

  stats.elapsedMs = now();
  return SearchOutput(
    hits,
    !timedOut,
    timedOut ? unexploredBound : null,
    stats,
  );
}

List<T> _stableSorted<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (final (i, v) in list.indexed) (i, v)];
  indexed.sort((a, b) {
    final d = compare(a.$2, b.$2);
    return d != 0 ? d : a.$1 - b.$1;
  });
  return [for (final (_, v) in indexed) v];
}
