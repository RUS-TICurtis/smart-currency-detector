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
  final bool autoScan;
  final double cameraZoom;
  final double confidenceThreshold;

  SettingsState({
    required this.speechRate, 
    required this.speechVolume, 
    required this.autoScan,
    required this.cameraZoom,
    required this.confidenceThreshold,
  });

  SettingsState copyWith({
    double? speechRate, 
    double? speechVolume, 
    bool? autoScan,
    double? cameraZoom,
    double? confidenceThreshold,
  }) {
    return SettingsState(
      speechRate: speechRate ?? this.speechRate,
      speechVolume: speechVolume ?? this.speechVolume,
      autoScan: autoScan ?? this.autoScan,
      cameraZoom: cameraZoom ?? this.cameraZoom,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
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
      autoScan: _settingsService.autoScan,
      cameraZoom: _settingsService.cameraZoom,
      confidenceThreshold: _settingsService.confidenceThreshold,
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

  Future<void> updateAutoScan(bool enabled) async {
    await _settingsService.setAutoScan(enabled);
    state = state.copyWith(autoScan: enabled);
  }

  Future<void> updateCameraZoom(double zoom) async {
    await _settingsService.setCameraZoom(zoom);
    state = state.copyWith(cameraZoom: zoom);
  }

  Future<void> updateConfidenceThreshold(double threshold) async {
    await _settingsService.setConfidenceThreshold(threshold);
    state = state.copyWith(confidenceThreshold: threshold);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});
