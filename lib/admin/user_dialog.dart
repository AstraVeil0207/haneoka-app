import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../chart_editor/project.dart';
import '../core/app_state.dart';
import '../ui/account_dialog.dart';
import '../ui/detail.dart';
import 'controller.dart';

class AdminUserDialog extends StatefulWidget {
  const AdminUserDialog({
    super.key,
    required this.controller,
    required this.document,
    required this.restrict,
  });
  final AdminController controller;
  final ChartMap document;
  final Future<void> Function(ChartMap user, String kind) restrict;

  @override
  State<AdminUserDialog> createState() => _AdminUserDialogState();
}

class _AdminUserDialogState extends State<AdminUserDialog> {
  late ChartMap _document = widget.document;
  bool _busy = false;
  ChartMap get _user => chartMap(_document['user']);
  String t(String key) => AppScope.of(context).text('admin.page.$key');
  String common(String key) => AppScope.of(context).text('common.$key');
  String value(Object? value) {
    if (value == null || value == '') return '—';
    if (value is bool) return common('states.${value ? 'yes' : 'no'}');
    final translated = t('values.$value');
    return translated.isEmpty ? '$value' : translated;
  }

  String date(Object? value) {
    if (value == null) return '—';
    final number = value is num ? value.toInt() : int.tryParse('$value');
    final parsed = number == null
        ? DateTime.tryParse('$value')
        : DateTime.fromMillisecondsSinceEpoch(number);
    return parsed?.toLocal().toString().split('.').first ?? '—';
  }

  Fact fact(String key, Object? v, {bool time = false}) =>
      Fact(t(key), time ? date(v) : value(v));

  Future<void> _refresh([Future<void> Function()? action]) async {
    if (_busy || !mounted) return;
    final controller = widget.controller;
    final owner = controller.ownerGeneration;
    final id = _user['id'];
    setState(() => _busy = true);
    try {
      await action?.call();
      if (!mounted || owner != controller.ownerGeneration) return;
      final document = await controller.request(
        '/api/v1/admin/users/$id',
        ownerGeneration: owner,
      );
      if (mounted) setState(() => _document = document);
    } catch (_) {
      if (mounted && owner == controller.ownerGeneration) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('actions.failed'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AccountDialog(
          child: AlertDialog(
            title: Text(title),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(common('actions.cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('actions.apply')),
              ),
            ],
          ),
        ),
      ) ==
      true;

  Widget _section(String key, List<Fact> facts, {bool open = false}) =>
      DetailFold(
        title: t(key),
        open: open,
        child: SpecList(facts: facts),
      );

  Widget _identity(ChartMap user) => _section('userDetails.identity', [
    fact('userDetails.accountId', user['id']),
    Fact(
      'UID',
      user['publicUid'] == null
          ? t('userDetails.uidUnassigned')
          : '${user['publicUid']}',
    ),
    fact('accountName', user['accountName']),
    fact('publicDisplayName', user['publicDisplayName']),
    fact('userDetails.handle', user['handle']),
    fact('userDetails.email', user['email']),
    fact('userDetails.emailVerified', user['emailVerified']),
    fact('userDetails.pendingName', user['candidateDisplayName']),
    fact('userDetails.nameReview', user['displayNameStatus']),
    Fact(t('columns.role'), t('roles.${user['role']}')),
    fact('columns.status', user['status']),
    fact('columns.createdAt', user['createdAt'], time: true),
    fact('workspace.updated', user['updatedAt'], time: true),
    fact('userDetails.profileCreated', user['profileCreatedAt'], time: true),
    fact('userDetails.profileUpdated', user['profileUpdatedAt'], time: true),
    fact('userDetails.profileDeleted', user['profileDeletedAt'], time: true),
    if (user['bio'] != null && user['bio'] != '')
      fact('userDetails.bio', user['bio']),
  ], open: true);

  Widget _visit() {
    final raw = _document['lastVisit'];
    if (raw == null) {
      return DetailFold(
        title: t('userDetails.latestVisit'),
        child: Text(t('userDetails.noVisit')),
      );
    }
    final visit = chartMap(raw);
    final location = chartMap(visit['ipLocation']);
    final network = chartMap(visit['network']);
    return _section('userDetails.latestVisit', [
      fact('ip.lastVisit', visit['visitedAt'], time: true),
      fact('ip.address', visit['ipAddress']),
      fact('ip.country', location['countryName'] ?? location['countryCode']),
      fact('ip.region', location['regionName'] ?? location['regionCode']),
      fact('ip.city', location['city']),
      fact('ip.postalCode', location['postalCode']),
      fact('ip.timezone', location['timezone']),
      if (location['latitude'] != null && location['longitude'] != null)
        fact(
          'ip.coordinates',
          '${location['latitude']}, ${location['longitude']}',
        ),
      fact('ip.asn', network['asn']),
      fact('ip.organization', network['organization']),
      fact('userDetails.countryCode', location['countryCode']),
      fact('userDetails.regionCode', location['regionCode']),
      fact('userDetails.continent', location['continent']),
    ]);
  }

  Widget _counts() {
    final counts = chartMap(_document['counts']);
    return DetailFold(
      title: t('userDetails.contentRecords'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (key, label, dimension) in [
            ('posts', 'sections.posts', 'moderation'),
            ('comments', 'history.comments', 'moderation'),
            ('attachments', 'workspace.attachments', 'status'),
          ]) ...[
            SpecList(facts: [fact(label, chartMap(counts[key])['total'])]),
            SpecList(
              facts: [
                for (final entry in chartMap(
                  chartMap(counts[key])[dimension],
                ).entries)
                  Fact(value(entry.key), value(entry.value)),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _providers() => DetailFold(
    title: t('userDetails.signInMethods'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final provider in chartRows(_document['providers']))
          DetailSection(
            icon: Symbols.key_rounded,
            title: provider['providerId'] == 'credential'
                ? t('userDetails.passwordSignIn')
                : value(provider['providerId']),
            child: SpecList(
              facts: [
                fact('userDetails.bindingCount', provider['bindingCount']),
                fact(
                  'userDetails.firstLinked',
                  provider['firstLinkedAt'],
                  time: true,
                ),
                fact(
                  'userDetails.lastLinkedUpdate',
                  provider['lastUpdatedAt'],
                  time: true,
                ),
                fact(
                  'userDetails.passwordCredential',
                  provider['hasPasswordCredential'],
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _history(String key, ChartMap user, bool canManage) {
    final document = chartMap(_document[key]);
    final rows = chartRows(document['items']);
    return DetailFold(
      title: t(
        key == 'restrictions'
            ? 'userDetails.restrictionHistory'
            : 'sections.operations',
      ),
      meta: '${rows.length} / ${document['total'] ?? 0}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            DetailSection(
              icon: Symbols.history_rounded,
              title: key == 'restrictions'
                  ? t('restrictions.${row['kind'] == 'sign_in' ? 'signIn' : row['kind']}')
                  : _operation(row['action']),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SpecList(
                    facts: [
                      fact('userDetails.recordId', row['id']),
                      fact(
                        'columns.status',
                        key != 'restrictions'
                            ? row['status']
                            : row['active'] == true
                            ? 'restricted'
                            : row['revokedAt'] != null
                            ? 'revoked'
                            : 'expired',
                      ),
                      fact('history.reason', row['reasonCode']),
                      fact('userDetails.actorUid', row['actorUserId']),
                      fact('columns.createdAt', row['createdAt'], time: true),
                      if (key == 'restrictions') ...[
                        Fact(
                          t('userDetails.expires'),
                          row['expiresAt'] == null
                              ? t('durations.permanent')
                              : date(row['expiresAt']),
                        ),
                        fact(
                          'userDetails.revokedAt',
                          row['revokedAt'],
                          time: true,
                        ),
                      ] else ...[
                        fact('columns.target', row['targetId']),
                        fact(
                          'userDetails.completed',
                          row['completedAt'],
                          time: true,
                        ),
                        fact('userDetails.errorCode', row['errorCode']),
                      ],
                    ],
                  ),
                  if (key == 'restrictions' && row['active'] == true)
                    TextButton(
                      onPressed: canManage
                          ? () async {
                              if (await _confirm(
                                t('actions.revokeRestriction'),
                              )) {
                                await _refresh(
                                  () => widget.controller.revokeRestriction(
                                    '${user['id']}',
                                    row,
                                  ),
                                );
                              }
                            }
                          : null,
                      child: Text(t('actions.revokeRestriction')),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _operation(Object? action) {
    final key = '$action'.replaceAllMapped(
      RegExp(r'[._-]([a-z])'),
      (match) => match[1]!.toUpperCase(),
    );
    final title = t('operations.actions.$key');
    return title.isEmpty ? value(action) : title;
  }

  @override
  Widget build(BuildContext context) {
    final user = _user, controller = widget.controller;
    final canManage =
        !_busy &&
        !controller.busy &&
        controller.staff['role'] == 'admin' &&
        user['version'] is num &&
        user['id'] != chartMap(controller.staff['user'])['id'];
    final sessions = chartMap(_document['sessions']);
    return AlertDialog(
      title: Text(
        '${user['publicDisplayName'] ?? user['accountName'] ?? t('userDetails.title')}',
      ),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  for (final (field, label) in [
                    ('id', 'userDetails.copyAccountId'),
                    ('publicUid', 'userDetails.copyUid'),
                  ])
                    TextButton.icon(
                      onPressed: user[field] == null
                          ? null
                          : () => Clipboard.setData(
                              ClipboardData(text: '${user[field]}'),
                            ),
                      icon: const Icon(Symbols.content_copy_rounded),
                      label: Text(t(label)),
                    ),
                ],
              ),
              _identity(user),
              _visit(),
              _counts(),
              _providers(),
              _section('userDetails.sessions', [
                fact('userDetails.storedSessions', sessions['stored']),
                fact('workspace.activeSessions', sessions['active']),
                fact('userDetails.expiredSessions', sessions['expired']),
                fact('userDetails.unknownExpiry', sessions['unknownExpiry']),
                fact(
                  'userDetails.sessionUpdated',
                  sessions['lastSessionUpdatedAt'],
                  time: true,
                ),
              ]),
              _history('restrictions', user, canManage),
              _history('operations', user, canManage),
              DetailFold(
                title: t('actions.manage'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey((user['id'], user['version'])),
                      initialValue: user['role'] as String?,
                      decoration: InputDecoration(labelText: t('columns.role')),
                      items: [
                        for (final role in adminRoles)
                          DropdownMenuItem(
                            value: role,
                            child: Text(t('roles.$role')),
                          ),
                      ],
                      onChanged: canManage
                          ? (role) async {
                              if (role != null &&
                                  role != user['role'] &&
                                  await _confirm(t('actions.role'))) {
                                await _refresh(
                                  () => controller.role(user, role),
                                );
                              }
                            }
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final kind in ['sign_in', 'upload', 'write'])
                          OutlinedButton(
                            onPressed: canManage
                                ? () => _refresh(
                                    () => widget.restrict(user, kind),
                                  )
                                : null,
                            child: Text(
                              t(
                                'restrictions.${kind == 'sign_in' ? 'signIn' : kind}',
                              ),
                            ),
                          ),
                        OutlinedButton(
                          onPressed: canManage
                              ? () async {
                                  if (await _confirm(
                                    t('actions.revokeSessions'),
                                  )) {
                                    await _refresh(
                                      () => controller.revokeSessions(user),
                                    );
                                  }
                                }
                              : null,
                          child: Text(t('actions.revokeSessions')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (_busy)
          const SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(),
          ),
        TextButton(
          onPressed: _busy ? null : _refresh,
          child: Text(t('refresh')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(common('actions.close')),
        ),
      ],
    );
  }
}
