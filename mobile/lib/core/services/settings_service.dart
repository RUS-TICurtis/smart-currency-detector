import 'package:hive_flutter/hive_flutter.dart';

class SettingsService {
  final Box _box = Hive.box('settings');

  static const String _speechRateKey = 'speechRate';
  static const String _speechVolumeKey = 'speechVolume';

  // Default values
  static const double defaultSpeechRate = 0.5;
  static const double defaultSpeechVolume = 1.0;

  double get speechRate => _box.get(_speechRateKey, defaultValue: defaultSpeechRate) as double;
  
  Future<void> setSpeechRate(double value) async {
    await _box.put(_speechRateKey, value);
  }

  double get speechVolume => _box.get(_speechVolumeKey, defaultValue: defaultSpeechVolume) as double;
  
  Future<void> setSpeechVolume(double value) async {
    await _box.put(_speechVolumeKey, value);
  }

  static const String _autoScanKey = 'autoScan';
  static const bool defaultAutoScan = false;

  bool get autoScan => _box.get(_autoScanKey, defaultValue: defaultAutoScan) as bool;
  
  Future<void> setAutoScan(bool value) async {
    await _box.put(_autoScanKey, value);
  }

  static const String _cameraZoomKey = 'cameraZoom';
  static const double defaultCameraZoom = 1.0;

  double get cameraZoom => _box.get(_cameraZoomKey, defaultValue: defaultCameraZoom) as double;
  
  Future<void> setCameraZoom(double value) async {
    await _box.put(_cameraZoomKey, value);
  }

  static const String _confidenceThresholdKey = 'confidenceThreshold';
  static const double defaultConfidenceThreshold = 0.75;

  double get confidenceThreshold => _box.get(_confidenceThresholdKey, defaultValue: defaultConfidenceThreshold) as double;

  Future<void> setConfidenceThreshold(double value) async {
    await _box.put(_confidenceThresholdKey, value);
  }
}
