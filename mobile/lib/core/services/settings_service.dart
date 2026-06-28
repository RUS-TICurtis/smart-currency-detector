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
}
