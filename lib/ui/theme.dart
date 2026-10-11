import 'package:flutter/material.dart';

/// Haneoka's navy, the colour of the suite's mark.
const haneokaSeed = Color(0xFF31356E);

ThemeData haneokaTheme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: haneokaSeed, brightness: brightness),
      useMaterial3: true,
    );
