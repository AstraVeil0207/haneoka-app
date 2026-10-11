import 'package:flutter/material.dart';

import 'schemes.g.dart';

/// Material 3 shape scale, as the website's tokens define it.
abstract final class Corner {
  static const extraSmall = 4.0,
      small = 8.0,
      medium = 12.0,
      large = 16.0,
      extraLarge = 28.0,
      full = 999.0;
}

/// The website's layout metrics.
abstract final class ShellMetrics {
  static const topBar = 64.0;
  static const rail = 96.0;
  static const drawer = 280.0;
  static const paneGap = 16.0;
  static const compact = 600.0;
  static const expanded = 1200.0;
}

ThemeData haneokaTheme(Brightness brightness, {String seed = 'haneoka'}) {
  final (light, dark) = haneokaSchemes[seed] ?? haneokaSchemes['haneoka']!;
  final scheme = brightness == Brightness.dark ? dark : light;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surfaceContainer,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      toolbarHeight: ShellMetrics.topBar,
      titleSpacing: 16,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corner.medium),
      ),
    ),
    listTileTheme: const ListTileThemeData(shape: StadiumBorder()),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      constraints: const BoxConstraints(
        minHeight: 48,
        maxHeight: 48,
        maxWidth: 360,
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      minWidth: ShellMetrics.rail,
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      indicatorShape: const StadiumBorder(),
    ),
  );
}
