import 'speech_service.dart';

class VoiceGuidanceService {
  final SpeechService _speechService;

  bool _hasPlayedOrientation = false;
  bool _hasHadFirstSuccessfulScan = false;

  VoiceGuidanceService(this._speechService);

  Future<void> playOrientation() async {
    if (_hasPlayedOrientation) return;

    _hasPlayedOrientation = true;
    await _speechService.speak(
        'Welcome to Smart Currency Detection. '
        'The Clear button is on your left. Press it once to remove the last scanned currency. Press and hold it to start a new session. '
        'The Sum button is in the middle. Press it to hear the total value of all scanned currency. '
        'The Scan button is on your right. Press it to scan a currency. '
        'To begin, press the Scan button on your right.'
    );
  }

  Future<void> announceScanSuccess(String spokenVal) async {
    if (!_hasHadFirstSuccessfulScan) {
      _hasHadFirstSuccessfulScan = true;
      await _speechService.speak(
          '$spokenVal detected. '
          'Press the Scan button on your right to add another currency. '
          'Press the Sum button in the middle to hear the total. '
          'Press the Clear button on your left to remove the last scanned currency.'
      );
    } else {
      await _speechService.speak(
          '$spokenVal detected. '
          'Press Scan to add another currency, or Sum to hear the total.'
      );
    }
  }

  Future<void> announceScanFailure() async {
    await _speechService.speak(
        'No currency detected. '
        'Hold the currency steady and try again. '
        'Press the Scan button on your right to scan again.'
    );
  }

  Future<void> announceSum(int itemCount, String spokenTotal) async {
    if (itemCount == 0) {
      await _speechService.speak(
          'No currency has been scanned yet. '
          'Press the Scan button on your right to begin.'
      );
    } else {
      String countWord = itemCount == 1 ? 'currency' : 'currencies';
      await _speechService.speak(
          'You have scanned $itemCount $countWord. '
          'Total value is $spokenTotal. '
          'Press Scan to continue adding currency, or Clear to remove the last scanned currency.'
      );
    }
  }

  Future<void> announceItemRemoved(String? spokenVal, String? spokenNewTotal, bool isNowEmpty) async {
    if (spokenVal == null) {
      await _speechService.speak('There is no scanned currency to remove.');
      return;
    }

    if (isNowEmpty) {
      await _speechService.speak(
          'Removed $spokenVal. '
          'Your session is now empty. '
          'Press the Scan button on your right to begin again.'
      );
    } else {
      await _speechService.speak(
          'Removed $spokenVal. '
          'Current total is $spokenNewTotal. '
          'Press Scan to continue.'
      );
    }
  }

  Future<void> announceSessionCleared(bool beforeClear) async {
    if (beforeClear) {
      await _speechService.speak('Starting a new session. All scanned currency will be removed.');
    } else {
      await _speechService.speak(
          'New session started. '
          'Press the Scan button on your right to scan your first currency.'
      );
    }
  }

  void resetSession() {
    _hasPlayedOrientation = false;
    _hasHadFirstSuccessfulScan = false;
  }
}
