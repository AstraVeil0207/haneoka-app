/// Saved teams, a hand-built formation and its evaluation across songs, with
/// the best card for one slot (`lit/team-builder/teams-tab.ts`).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../ui/theme.dart';
import 'box.dart';
import 'controller.dart';
import 'engine/api.dart';
import 'engine/box.dart';
import 'engine/objectives.dart' show RouteKind;
import 'engine_client.dart';
import 'pickers.dart';
import 'widgets.dart';

class TeamsTab extends StatefulWidget {
  const TeamsTab({super.key, required this.controller});
  final TeamBuilderController controller;

  @override
  State<TeamsTab> createState() => _TeamsTabState();
}

class _TeamsTabState extends State<TeamsTab> {
  ({int slot, List<EngineHit> hits})? _suggestions;
  int _suggesting = -1;

  TeamBuilderController get c => widget.controller;
  ManualTeam get manual => c.manual;

  bool get _ready =>
      manual.members.every((id) => id != null) &&
      {
            for (final id in manual.members)
              c.catalog!.characterIds(true, id!).firstOrNull,
          }.length ==
          5;

  void _set(ManualTeam team) {
    c.manual = team;
    c.manualResults = null;
    _suggestions = null;
    c.changed();
  }

  TeamSpec get _spec => TeamSpec(
    [for (final id in manual.members) 'm$id'],
    [for (final id in manual.snaps) id == null ? null : 's$id'],
    'm${manual.members[manual.leader]}',
  );

  /// Engine inputs that always contain the manual team's own cards.
  ({
    List<MemberInput> members,
    List<SnapInput> snaps,
    PlayerInput player,
    UnknownPolicy policy,
  })
  _inputs() {
    final request = c.request();
    final view = c.view!;
    final cards = request != null
        ? (members: request.members, snaps: request.snaps)
        : c.engineCards();
    final members = [...cards.members];
    final snaps = [...cards.snaps];
    for (final id in manual.members) {
      if (id != null && !members.any((row) => row.cardId == id)) {
        final owned = view.members[id];
        members.add(
          MemberInput(
            key: 'm$id',
            cardId: id,
            level: owned?.level,
            awake: owned?.awake,
            rank: owned?.rank,
            liveSkillLevel: owned?.skill,
            gekisoSkillLevel: owned?.gekisoSkill,
          ),
        );
      }
    }
    for (final id in manual.snaps) {
      if (id != null && !snaps.any((row) => row.cardId == id)) {
        final owned = view.snaps[id];
        snaps.add(
          SnapInput(
            key: 's$id',
            cardId: id,
            level: owned?.level,
            rank: owned?.rank,
          ),
        );
      }
    }
    return (
      members: members,
      snaps: snaps,
      player: view.player,
      policy:
          request?.unknownPolicy ??
          (c.settings.unknownPolicy == 'min'
              ? UnknownPolicy.min
              : UnknownPolicy.max),
    );
  }

  Future<void> _evaluate() async {
    final engine = c.engine;
    final s = c.settings;
    if (!_ready || engine == null || s.songs.isEmpty || c.running) return;
    c.manualBusy = true;
    c.changed();
    final inputs = _inputs();
    try {
      c.manualResults = await engine.evaluate(
        EvaluateRequest(
          members: inputs.members,
          snaps: inputs.snaps,
          player: inputs.player,
          unknownPolicy: inputs.policy,
          team: _spec,
          songs: s.songs,
          play: c.play,
          challengeEventId: s.challengeRules ? s.eventId : null,
          event:
              s.eventId != null &&
                  (s.goal.name == 'event' || s.goal.name == 'plan') &&
                  s.route != 'skip'
              ? (
                  eventId: s.eventId!,
                  route: s.route == 'challenge'
                      ? RouteKind.challenge
                      : RouteKind.live,
                  consumption: s.route == 'challenge'
                      ? s.challengePoints
                      : s.boosts,
                )
              : null,
        ),
      );
    } on EngineCancelled {
      // Cancelled.
    } catch (error) {
      c.error = '$error';
    } finally {
      c.manualBusy = false;
      c.changed();
    }
  }

  /// Best cards for one slot with the other four fixed (exact constrained search).
  Future<void> _suggest(int slot) async {
    final base = c.request();
    final engine = c.engine;
    if (base == null || engine == null || !_ready || c.running) return;
    setState(() => _suggesting = slot);
    final others = [
      for (final (index, id) in manual.members.indexed)
        if (index != slot && id != null)
          (
            member: id,
            snap: manual.snaps[index],
            leader: index == manual.leader,
          ),
    ];
    final inputs = _inputs();
    try {
      final result = await engine.run(
        EngineRequest(
          members: inputs.members,
          snaps: inputs.snaps,
          player: base.player,
          unknownPolicy: base.unknownPolicy,
          goal: base.goal,
          constraints: ConstraintInput(
            requiredMembers: [for (final row in others) 'm${row.member}'],
            requiredSnaps: base.constraints.requiredSnaps,
            excludedSnaps: base.constraints.excludedSnaps,
            leader: slot == manual.leader
                ? null
                : 'm${manual.members[manual.leader]}',
            bindings: [
              for (final row in others)
                ('m${row.member}', row.snap == null ? null : 's${row.snap}'),
            ],
            noSnaps: base.constraints.noSnaps,
            minBonusPercent: base.constraints.minBonusPercent,
          ),
          k: 3,
          timeLimitMs: base.timeLimitMs,
        ),
      );
      _suggestions = (slot: slot, hits: result.overall.take(3).toList());
    } on EngineCancelled {
      // Cancelled.
    } catch (error) {
      c.error = '$error';
    } finally {
      if (mounted) setState(() => _suggesting = -1);
    }
  }

  Future<void> _pick(int slot, bool members) async {
    final catalog = c.catalog!;
    final view = c.view!;
    final theoretical = c.settings.theoretical;
    final ids = theoretical
        ? [
            for (final key in objectKeys(
              catalog.data[members ? 'members' : 'snapshots'],
            ))
              ?int.tryParse(key),
          ]
        : [...(members ? view.members.keys : view.snaps.keys)];
    final current = members ? manual.members[slot] : manual.snaps[slot];
    final picked = await pickCard(
      context,
      catalog,
      members: members,
      ids: ids,
      current: current,
    );
    if (picked == null) return;
    final list = [...(members ? manual.members : manual.snaps)];
    if (picked < 0) {
      list[slot] = null;
    } else {
      // A card can sit in one slot only; picking it again moves it.
      for (var i = 0; i < list.length; i++) {
        if (list[i] == picked) list[i] = null;
      }
      list[slot] = picked;
    }
    _set(
      members ? manual.copyWith(members: list) : manual.copyWith(snaps: list),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = c.catalog!;
    final view = c.view!;
    final theme = Theme.of(context);
    final locale = c.state.text.locale;
    final visual = [
      for (var i = 0; i < 5; i++)
        if (i != manual.leader) i,
    ]..insert(2, manual.leader);
    final characters = [
      for (final id in manual.members)
        id == null ? null : catalog.characterIds(true, id).firstOrNull,
    ];
    final duplicate = [
      for (final (i, id) in characters.indexed)
        if (id != null && characters.indexOf(id) != i) id,
    ].isNotEmpty;
    final results = c.manualResults;
    final s = c.settings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ToolSection(
          icon: Symbols.edit_square_rounded,
          title: c.tb('manualTeam', 'Build a team by hand'),
          trailing: Wrap(
            children: [
              TextButton.icon(
                onPressed: _ready
                    ? () {
                        c.saveTeam(
                          [
                            manual.members[manual.leader]!,
                            for (final (i, id) in manual.members.indexed)
                              if (i != manual.leader) id!,
                          ],
                          [
                            manual.snaps[manual.leader],
                            for (final (i, id) in manual.snaps.indexed)
                              if (i != manual.leader) id,
                          ],
                          s.songs.firstOrNull,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(c.tb('savedTeam', 'Saved to Teams')),
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Symbols.bookmark_add_rounded),
                label: Text(c.tb('saveTeam', 'Save team')),
              ),
              TextButton(
                onPressed: () => _set(const ManualTeam()),
                child: Text(catalog.t('common.actions.clear', 'Clear')),
              ),
            ],
          ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final slot in visual)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: DecoratedBox(
                        decoration: slot == manual.leader
                            ? BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(
                                  Corner.medium,
                                ),
                                border: Border.all(
                                  color: theme.colorScheme.primary,
                                  width: 2,
                                ),
                              )
                            : const BoxDecoration(),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            children: [
                              _SlotButton(
                                onTap: () => _pick(slot, true),
                                members: true,
                                child: manual.members[slot] == null
                                    ? const Icon(Symbols.person_add_rounded)
                                    : CardArt(
                                        catalog: catalog,
                                        members: true,
                                        id: manual.members[slot]!,
                                      ),
                              ),
                              const SizedBox(height: 4),
                              _SlotButton(
                                onTap: () => _pick(slot, false),
                                members: false,
                                child: manual.snaps[slot] == null
                                    ? const Icon(
                                        Symbols.add_photo_alternate_rounded,
                                        size: 20,
                                      )
                                    : CardArt(
                                        catalog: catalog,
                                        members: false,
                                        id: manual.snaps[slot]!,
                                      ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 36,
                                child: Center(
                                  child: slot == manual.leader
                                      ? DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            child: FittedBox(
                                              child: Text(
                                                c.tb('leader', 'Leader'),
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onPrimary,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        )
                                      : TextButton(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            minimumSize: const Size(0, 36),
                                          ),
                                          onPressed:
                                              manual.members[slot] == null
                                              ? null
                                              : () => _set(
                                                  manual.copyWith(leader: slot),
                                                ),
                                          child: FittedBox(
                                            child: Text(
                                              c.tb('makeLeader', 'Leader'),
                                              maxLines: 1,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              IconButton(
                                tooltip: c.tb(
                                  'suggestSlot',
                                  'Best card for this slot',
                                ),
                                onPressed:
                                    !_ready ||
                                        _suggesting >= 0 ||
                                        c.request() == null
                                    ? null
                                    : () => _suggest(slot),
                                icon: const Icon(
                                  Symbols.auto_fix_high_rounded,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (duplicate)
              Text(
                c.tb('duplicateCharacter', 'Each character can appear once.'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (_suggesting >= 0) const LinearProgressIndicator(),
            if (_suggestions case final suggestions?) ...[
              Text(
                c.tb('suggestions', 'Best replacements'),
                style: theme.textTheme.titleSmall,
              ),
              if (suggestions.hits.isEmpty)
                Text(c.tb('noSuggestion', 'No better card found.')),
              for (final hit in suggestions.hits)
                if (hit.members
                        .where((key) => !manual.members.contains(cardIdOf(key)))
                        .firstOrNull
                    case final member?)
                  () {
                    final index = hit.members.indexOf(member);
                    final snap = hit.snaps[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                        width: 40,
                        child: CardArt(
                          catalog: catalog,
                          members: true,
                          id: cardIdOf(member),
                          emblems: false,
                        ),
                      ),
                      title: Text(catalog.cardName(true, cardIdOf(member))),
                      subtitle: Text(
                        [
                          snap == null
                              ? c.tb('noSnap', 'No snap')
                              : catalog.cardName(false, cardIdOf(snap)),
                          '${c.tb('power', 'Power')} ${formatNumber(locale, hit.power)}',
                          if (hit.score != null)
                            formatNumber(locale, hit.score!.mean),
                          if (hit.event != null)
                            '${formatNumber(locale, hit.event!.mean, 1)} pt',
                        ].join(' · '),
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () {
                          final members = [...manual.members];
                          final snaps = [...manual.snaps];
                          members[suggestions.slot] = cardIdOf(member);
                          snaps[suggestions.slot] = snap == null
                              ? null
                              : cardIdOf(snap);
                          _set(manual.copyWith(members: members, snaps: snaps));
                        },
                        child: Text(c.tb('apply', 'Apply')),
                      ),
                    );
                  }(),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed:
                      !_ready ||
                          duplicate ||
                          s.songs.isEmpty ||
                          c.manualBusy ||
                          c.running
                      ? null
                      : _evaluate,
                  icon: const Icon(Symbols.calculate_rounded),
                  label: Text(
                    c.tb('evaluateTeam', 'Evaluate on the chosen songs'),
                  ),
                ),
                Text(
                  s.songs.isNotEmpty
                      ? c.tb('evaluateSongs', '{count} songs from Build', {
                          'count': s.songs.length,
                        })
                      : c.tb('needSongs', 'Choose at least one song.'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (c.manualBusy) const LinearProgressIndicator(),
            if (results != null)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    DataColumn(label: Text(c.tb('song', 'Song'))),
                    DataColumn(
                      label: Text(c.tb('power', 'Power')),
                      numeric: true,
                    ),
                    DataColumn(
                      label: Text(c.tb('expectedScore', 'Expected score')),
                      numeric: true,
                    ),
                    DataColumn(label: Text(c.tb('scoreRange', 'Range'))),
                    DataColumn(
                      label: Text(c.tb('skipScore', 'Skip score')),
                      numeric: true,
                    ),
                    if (results.any((row) => row.event != null)) ...[
                      DataColumn(
                        label: Text(
                          c.tb('pointsPerPlay', 'Event points per play'),
                        ),
                        numeric: true,
                      ),
                      DataColumn(
                        label: Text(c.tb('itemsPerPlay', 'Items per play')),
                        numeric: true,
                      ),
                    ],
                  ],
                  rows: [
                    for (final row in [
                      ...results,
                    ]..sort((a, b) => b.score.mean.compareTo(a.score.mean)))
                      DataRow(
                        cells: [
                          DataCell(
                            Text(
                              '${catalog.songTitle(row.song.songId)} ${catalog.difficultyLabel(row.song.songId, row.song.difficulty)}',
                            ),
                          ),
                          DataCell(Text(formatNumber(locale, row.power))),
                          DataCell(Text(formatNumber(locale, row.score.mean))),
                          DataCell(
                            Text(
                              '${formatNumber(locale, row.score.min)} – ${formatNumber(locale, row.score.max)}',
                            ),
                          ),
                          DataCell(Text(formatNumber(locale, row.skipScore))),
                          if (results.any((r) => r.event != null)) ...[
                            DataCell(
                              Text(
                                row.event == null
                                    ? ''
                                    : '${formatNumber(locale, row.event!.points, 1)} (+${formatNumber(locale, row.event!.bonusPercent.floor())}%)',
                              ),
                            ),
                            DataCell(
                              Text(
                                row.event == null
                                    ? ''
                                    : formatNumber(locale, row.event!.items, 1),
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        ToolSection(
          icon: Symbols.bookmarks_rounded,
          title: c.tb('savedTeams', 'Saved teams'),
          count: view.teams.isEmpty ? null : '${view.teams.length}',
          children: [
            if (view.teams.isEmpty)
              Text(c.tb('noSavedTeamsShort', 'No saved teams'))
            else
              for (final team in view.teams)
                _SavedTeamCard(
                  controller: c,
                  team: team,
                  onOpen: () {
                    // Saved order is leader first; the editor shows the leader in the centre.
                    List<int?> centred(List<int?> list) => [
                      list.elementAtOrNull(1),
                      list.elementAtOrNull(2),
                      list.elementAtOrNull(0),
                      list.elementAtOrNull(3),
                      list.elementAtOrNull(4),
                    ];
                    _set(
                      ManualTeam(
                        members: centred(team.members),
                        snaps: centred(team.snaps),
                      ),
                    );
                    if (team.song case final song?
                        when !s.songs.any((x) => x.songId == song.songId)) {
                      c.updateSettings({
                        'songs': [
                          for (final x in [...s.songs, song]) x.toJson(),
                        ],
                      });
                    }
                    PrimaryScrollController.maybeOf(context)?.animateTo(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                ),
          ],
        ),
      ],
    );
  }
}

Iterable<String> objectKeys(Object? value) =>
    value is Map ? value.keys.map((key) => '$key') : const [];

class _SlotButton extends StatelessWidget {
  const _SlotButton({
    required this.onTap,
    required this.members,
    required this.child,
  });
  final VoidCallback onTap;
  final bool members;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(Corner.small),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: members ? 3 / 4 : 16 / 9,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _SavedTeamCard extends StatefulWidget {
  const _SavedTeamCard({
    required this.controller,
    required this.team,
    required this.onOpen,
  });
  final TeamBuilderController controller;
  final SavedTeam team;
  final VoidCallback onOpen;

  @override
  State<_SavedTeamCard> createState() => _SavedTeamCardState();
}

class _SavedTeamCardState extends State<_SavedTeamCard> {
  late final _name = TextEditingController(text: widget.team.name);

  @override
  void didUpdateWidget(_SavedTeamCard old) {
    super.didUpdateWidget(old);
    if (old.team.name != widget.team.name && _name.text != widget.team.name) {
      _name.text = widget.team.name;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _rename(String value) {
    final team = widget.team;
    final name = value.length > 80 ? value.substring(0, 80) : value;
    if (name == team.name) return;
    widget.controller.write([
      ('team.${team.id}', {...team.toJson(), 'name': name}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final catalog = c.catalog!;
    final team = widget.team;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(Corner.large),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: c.tb('teamName', 'Name'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: _rename,
                      onTapOutside: (_) => _rename(_name.text),
                    ),
                  ),
                  IconButton(
                    tooltip: c.tb('loadTeam', 'Open in the editor'),
                    onPressed: widget.onOpen,
                    icon: const Icon(Symbols.edit_rounded),
                  ),
                  IconButton(
                    tooltip: catalog.t('common.actions.delete', 'Delete'),
                    onPressed: () {
                      c.write([('team.${team.id}', null)]);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(c.tb('deletedTeam', 'Team deleted')),
                        ),
                      );
                    },
                    icon: const Icon(Symbols.delete_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (index, id) in team.members.indexed)
                    if (catalog.has(true, id))
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: DecoratedBox(
                            position: DecorationPosition.foreground,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Corner.small),
                              border: index == 0
                                  ? Border.all(
                                      color: theme.colorScheme.primary,
                                      width: 2,
                                    )
                                  : null,
                            ),
                            child: CardArt(
                              catalog: catalog,
                              members: true,
                              id: id,
                              emblems: false,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
              if (team.song case final song?)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${catalog.songTitle(song.songId)} ${catalog.difficultyLabel(song.songId, song.difficulty)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
