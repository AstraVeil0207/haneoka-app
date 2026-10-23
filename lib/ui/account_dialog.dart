import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/account_resource.dart';

/// Dialog data and pending actions belong to the account that opened them.
class AccountDialog extends StatefulWidget {
  const AccountDialog({super.key, required this.child});
  final Widget child;
  @override
  State<AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<AccountDialog> {
  late final _epoch = AccountResources.instance.epoch;
  StreamSubscription<void>? _changes;
  bool _revoked = false;
  @override
  void initState() {
    super.initState();
    _changes = AccountResources.instance.changes.listen((_) {
      if (!mounted || _epoch == AccountResources.instance.epoch) return;
      setState(() => _revoked = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route != null && route.isActive) {
          Navigator.of(context).removeRoute(route);
        }
      });
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _revoked ? const SizedBox.shrink() : widget.child;
}
