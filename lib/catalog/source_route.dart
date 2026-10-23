import 'package:flutter/material.dart';

import '../core/catalog_source.dart';
import '../core/private_content_api.dart';
import '../core/app_state.dart';
import '../shell/page.dart';
import '../shell/route_paths.dart';
import '../shell/routes.dart';

class NativeCatalogSourceRoute extends StatefulWidget {
  const NativeCatalogSourceRoute({
    super.key,
    required this.source,
    required this.route,
  });
  final String source;
  final Uri route;
  @override
  State<NativeCatalogSourceRoute> createState() =>
      _NativeCatalogSourceRouteState();
}

class _NativeCatalogSourceRouteState extends State<NativeCatalogSourceRoute> {
  PrivateContentApi? _api;
  @override
  void initState() {
    super.initState();
    if (RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(widget.source)) {
      _api = PrivateContentApi(server: widget.source)..addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    if (api == null) {
      return ShellPage(
        title: AppScope.of(context).text('common.fields.source'),
        body: Center(
          child: Text(AppScope.of(context).text('common.states.unavailable')),
        ),
      );
    }
    final uri = widget.route.replace(path: canonicalAppPath(widget.route.path));
    return CatalogSourceScope(
      key: ValueKey((api, api.revision)),
      api: api,
      child: KeyedSubtree(
        key: ValueKey((api, api.revision)),
        child: Builder(
          builder: (context) =>
              screenFor(
                uri.toString(),
                navigate: ShellScope.of(context)!.navigate,
              ) ??
              PendingScreen(label: 'common.states.unavailable'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _api?.removeListener(_changed);
    _api?.dispose();
    super.dispose();
  }
}
