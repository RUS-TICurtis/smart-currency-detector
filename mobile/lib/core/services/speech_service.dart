import 'package:flutter_tts/flutter_tts.dart';
import 'settings_service.dart';

class SpeechService {
  final FlutterTts _flutterTts = FlutterTts();
  final SettingsService _settingsService;
  bool _isReady = false;

  SpeechService(this._settingsService) {
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    _isReady = true;
  }

  Future<void> speak(String text) async {
    if (!_isReady) return;
    
    // Apply latest settings right before speaking
    await _flutterTts.setSpeechRate(_settingsService.speechRate);
    await _flutterTts.setVolume(_settingsService.speechVolume);
    await _flutterTts.setPitch(1.0);
    
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    if (!_isReady) return;
    await _flutterTts.stop();
  }
}
