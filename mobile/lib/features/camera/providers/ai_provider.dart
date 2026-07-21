import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/ai_model_service.dart';

/// FIX (C-02 / H-02): Use a FutureProvider so the service is only available
/// AFTER [initModel] has fully completed.  Previously the model was loaded
/// fire-and-forget, allowing inference calls to arrive while _interpreter was
/// still null — silently returning null on every frame.
///
/// BUG-05 FIX: Removed autoDispose. The TFLite interpreter is expensive to
/// load (~0.5-2s) and should persist for the entire app session. autoDispose
/// was destroying the model on every navigation away from CameraScreen.
final aiServiceProvider = FutureProvider<AIModelService>((ref) async {
  final service = AIModelService();
  // This awaits the full async model load (10.6 MB TFLite file + labels).
  await service.initModel();
  return service;
});
