import 'package:flutter_tts/flutter_tts.dart';
import 'settings_service.dart';

class SpeechService {
  final FlutterTts _flutterTts = FlutterTts();
  final SettingsService _settingsService;

  // FIX (H-08): Track the initialisation Future so speak() can always await
  // it, preventing the "first announcement silently dropped" race condition.
  late final Future<void> _initFuture;

  SpeechService(this._settingsService) {
    _initFuture = _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('en-US');
  }

  Future<void> speak(String text) async {
    // Ensure TTS engine is ready before attempting to speak.
    await _initFuture;

    // FIX (L-07): Stop any ongoing speech before starting a new utterance to
    // prevent overlapping announcements during rapid auto-scan detections.
    await _flutterTts.stop();

    // Apply latest user settings immediately before each utterance.
    await _flutterTts.setSpeechRate(_settingsService.speechRate);
    await _flutterTts.setVolume(_settingsService.speechVolume);
    await _flutterTts.setPitch(1.0);

    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _initFuture;
    await _flutterTts.stop();
  }
}
