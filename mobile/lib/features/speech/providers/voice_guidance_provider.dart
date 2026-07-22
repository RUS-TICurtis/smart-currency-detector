import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/voice_guidance_service.dart';
import 'speech_provider.dart';

final voiceGuidanceProvider = Provider<VoiceGuidanceService>((ref) {
  final speechService = ref.watch(speechServiceProvider);
  return VoiceGuidanceService(speechService);
});
