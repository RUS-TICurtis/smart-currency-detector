import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/settings_service.dart';

// Provider for the SettingsService
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});

// A State class to hold the current settings
class SettingsState {
  final double speechRate;
  final double speechVolume;

  SettingsState({required this.speechRate, required this.speechVolume});

  SettingsState copyWith({double? speechRate, double? speechVolume}) {
    return SettingsState(
      speechRate: speechRate ?? this.speechRate,
      speechVolume: speechVolume ?? this.speechVolume,
    );
  }
}

class SettingsNotifier extends Notifier<SettingsState> {
  late final SettingsService _settingsService;

  @override
  SettingsState build() {
    _settingsService = ref.watch(settingsServiceProvider);
    return SettingsState(
      speechRate: _settingsService.speechRate,
      speechVolume: _settingsService.speechVolume,
    );
  }

  Future<void> updateSpeechRate(double rate) async {
    await _settingsService.setSpeechRate(rate);
    state = state.copyWith(speechRate: rate);
  }

  Future<void> updateSpeechVolume(double volume) async {
    await _settingsService.setSpeechVolume(volume);
    state = state.copyWith(speechVolume: volume);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});
