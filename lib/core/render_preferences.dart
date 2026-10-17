import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent host choices; renderers receive only the numeric configuration.
final class RenderPreferences extends ChangeNotifier {
  RenderPreferences(this._prefs)
    : factor = _factor(
        _prefs.getDouble('rendering.factor') ??
            double.tryParse(
              const String.fromEnvironment('HANEOKA_SPATIAL_UPSCALE'),
            ) ??
            1,
      ),
      sharpness = (_prefs.getDouble('rendering.sharpness') ?? .8705505632961241)
          .clamp(0, 1);
  final SharedPreferences _prefs;
  double factor;
  double sharpness;
  static double _factor(double value) =>
      const [1.0, 1.3, 1.5].contains(value) ? value : 1;

  Future<void> reset() async {
    if (factor == 1 && sharpness == .8705505632961241) return;
    factor = 1;
    sharpness = .8705505632961241;
    notifyListeners();
    await Future.wait([
      _prefs.setDouble('rendering.factor', factor),
      _prefs.setDouble('rendering.sharpness', sharpness),
    ]);
  }

  Future<void> setFactor(double value) async {
    final next = _factor(value);
    if (next == factor) return;
    factor = next;
    notifyListeners();
    await _prefs.setDouble('rendering.factor', next);
  }

  Future<void> setSharpness(double value) async {
    if (!value.isFinite) return;
    final next = value.clamp(0.0, 1.0);
    if (next == sharpness) return;
    sharpness = next;
    notifyListeners();
    await _prefs.setDouble('rendering.sharpness', next);
  }
}
