/// The team builder: Build, My cards, Account bonuses and Teams, over the
/// box synced with the website (`lit/team-builder.ts`).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../account/account_widgets.dart';
import '../account/haneoka_account.dart';
import '../core/app_state.dart';
import '../l10n/app_localizations.dart';
import '../save/game_save.dart';
import '../shell/page.dart';
import '../ui/labels.dart';
import 'account_tab.dart';
import 'box.dart';
import 'box_import_screen.dart';
import 'box_tab.dart';
import 'build_tab.dart';
import 'controller.dart';
import 'pt_tab.dart';
import 'teams_tab.dart';
import 'widgets.dart';

enum _Tab { build, pt, box, account, teams }

class TeamBuilderScreen extends StatefulWidget {
  const TeamBuilderScreen({super.key, this.importSave});
  final GameSave? importSave;

  @override
  State<TeamBuilderScreen> createState() => _TeamBuilderScreenState();
}

class _TeamBuilderScreenState extends State<TeamBuilderScreen> {
  TeamBuilderController? _controller;
  _Tab _tab = _Tab.build;
  String _query = '';
  String? _errorShown;
  bool _importOpened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    final controller = _controller ??= TeamBuilderController(
      state,
      serverOverride: widget.importSave?.release?.server,
    )..addListener(_changed);
    controller.load();
  }

  void _changed() {
    final c = _controller;
    if (!_importOpened &&
        widget.importSave != null &&
        c?.catalog != null &&
        c?.view != null) {
      _importOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          openBoxImport(
            context,
            c!,
            members: true,
            initialSave: widget.importSave,
          );
        }
      });
    }
    final error = _controller?.error;
    if (error != null && error != _errorShown) {
      _errorShown = error;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(error), duration: const Duration(seconds: 8)),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    final t = c.state.text;
    final ready = c.catalog != null && c.view != null;
    final store = c.store;
    final sync = switch (store?.status) {
      BoxSyncStatus.syncing => (
        Symbols.sync_rounded,
        c.tb('syncing', 'Syncing…'),
      ),
      BoxSyncStatus.pending => (
        Symbols.schedule_rounded,
        c.tb('syncPending', 'Saving…'),
      ),
      BoxSyncStatus.synced => (
        Symbols.cloud_done_rounded,
        c.tb('synced', 'Synced'),
      ),
      BoxSyncStatus.offline => (
        Symbols.cloud_off_rounded,
        c.tb('syncOffline', 'Offline · changes are kept and sent later'),
      ),
      BoxSyncStatus.signedOut => (
        Symbols.no_accounts_rounded,
        c.tb('syncSignedOut', 'Sign in again to sync'),
      ),
      BoxSyncStatus.error => (
        Symbols.error_rounded,
        c.tb('syncError', 'Sync paused'),
      ),
      _ => (
        Symbols.save_rounded,
        c.tb('syncLocal', 'Saved on this device · sign in to sync'),
      ),
    };
    final tabs = [
      (_Tab.build, Symbols.groups_rounded, c.tb('tabBuild', 'Build'), null),
      (
        _Tab.pt,
        Symbols.emoji_events_rounded,
        c.tb('pt.tab', 'Event rewards'),
        null,
      ),
      (
        _Tab.box,
        Symbols.style_rounded,
        c.tb('tabBox', 'My cards'),
        ready && c.view!.members.length + c.view!.snaps.length > 0
            ? c.view!.members.length + c.view!.snaps.length
            : null,
      ),
      (
        _Tab.account,
        Symbols.trending_up_rounded,
        c.tb('tabAccount', 'Account bonuses'),
        null,
      ),
      (
        _Tab.teams,
        Symbols.bookmark_rounded,
        c.tb('tabTeams', 'Teams'),
        ready && c.view!.teams.isNotEmpty ? c.view!.teams.length : null,
      ),
    ];
    final Widget body;
    if (!ready) {
      body = Center(
        child: c.loadError != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.tb('loadFailed', 'Card data could not be loaded.')),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: c.load,
                    child: Text(t('common.actions.retry', 'Retry')),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(c.tb('loadingData', 'Loading card data')),
                ],
              ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: PillTabs<_Tab>(
              value: _tab,
              tabs: tabs,
              onSelected: (tab) => setState(() {
                _tab = tab;
                c.activity = tab == _Tab.pt;
              }),
            ),
          ),
          Expanded(
            child: switch (_tab) {
              _Tab.build => BuildTab(controller: c),
              _Tab.pt => PtTab(
                controller: c,
                openTab: (name) => setState(
                  () => _tab = name == 'account' ? _Tab.account : _Tab.box,
                ),
              ),
              _Tab.box => BoxTab(controller: c, query: _query),
              _Tab.account => AccountTab(controller: c),
              _Tab.teams => TeamsTab(controller: c),
            },
          ),
        ],
      );
    }
    return ShellPage(
      showBack: widget.importSave != null,
      key: ValueKey(_tab == _Tab.box),
      title: widget.importSave?.release == null
          ? c.tb('title', 'Team builder')
          : '${c.tb('title', 'Team builder')} · ${widget.importSave!.release!.label(AppLocalizations.of(context))}',
      search: ready && _tab == _Tab.box
          ? ShellSearch(
              label: t('common.actions.search', 'Search'),
              initial: _query,
              onChanged: (value) => setState(() => _query = value),
            )
          : null,
      actions: [
        if (store != null)
          HaneokaAccount.instance.signedIn &&
                  store.status != BoxSyncStatus.signedOut
              ? BarAction(
                  icon: sync.$1,
                  label: sync.$2,
                  onPressed: store.refresh,
                )
              : BarAction(
                  icon: Symbols.cloud_sync_rounded,
                  label: c.tb('syncSignIn', 'Sign in to sync'),
                  showLabel: true,
                  onPressed: () async {
                    await signInToHaneoka(context);
                    if (mounted) await store.refresh();
                  },
                ),
      ],
      body: body,
    );
  }
}
