import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/speech_service.dart';
import '../../settings/providers/settings_provider.dart';

final speechServiceProvider = Provider<SpeechService>((ref) {
  final settingsService = ref.watch(settingsServiceProvider);
  final service = SpeechService(settingsService);
  ref.onDispose(() {
    service.stop();
  });
  return service;
});
