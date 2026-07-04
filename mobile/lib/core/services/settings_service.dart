import 'package:hive_flutter/hive_flutter.dart';

/// Persists user preferences to Hive local storage.
///
/// FIX (M-06): All getters use `(value as num).toDouble()` instead of a hard
/// `as double` cast.  Hive may store integers (e.g. `1` instead of `1.0`) if
/// a previous app version wrote them that way; the previous cast would throw a
/// [TypeError] on startup and crash the app.
class SettingsService {
  final Box _box = Hive.box('settings');

  // ── Keys ──
  static const String _speechRateKey = 'speechRate';
  static const String _speechVolumeKey = 'speechVolume';
  static const String _autoScanKey = 'autoScan';
  static const String _cameraZoomKey = 'cameraZoom';
  static const String _confidenceThresholdKey = 'confidenceThreshold';

  // ── Defaults ──
  static const double defaultSpeechRate = 0.5;
  static const double defaultSpeechVolume = 1.0;
  static const bool defaultAutoScan = false;
  static const double defaultCameraZoom = 1.0;
  static const double defaultConfidenceThreshold = 0.75;

  // ── Speech rate ──
  double get speechRate =>
      (_box.get(_speechRateKey, defaultValue: defaultSpeechRate) as num)
          .toDouble();

  Future<void> setSpeechRate(double value) async =>
      _box.put(_speechRateKey, value);

  // ── Speech volume ──
  double get speechVolume =>
      (_box.get(_speechVolumeKey, defaultValue: defaultSpeechVolume) as num)
          .toDouble();

  Future<void> setSpeechVolume(double value) async =>
      _box.put(_speechVolumeKey, value);

  // ── Auto scan ──
  bool get autoScan =>
      _box.get(_autoScanKey, defaultValue: defaultAutoScan) as bool;

  Future<void> setAutoScan(bool value) async =>
      _box.put(_autoScanKey, value);

  // ── Camera zoom ──
  double get cameraZoom =>
      (_box.get(_cameraZoomKey, defaultValue: defaultCameraZoom) as num)
          .toDouble();

  Future<void> setCameraZoom(double value) async =>
      _box.put(_cameraZoomKey, value);

  // ── Confidence threshold ──
  double get confidenceThreshold => (_box.get(
        _confidenceThresholdKey,
        defaultValue: defaultConfidenceThreshold,
      ) as num)
          .toDouble();

  Future<void> setConfidenceThreshold(double value) async =>
      _box.put(_confidenceThresholdKey, value);
}
