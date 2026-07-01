import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/ai_model_service.dart';

final aiServiceProvider = Provider<AIModelService>((ref) {
  final service = AIModelService();
  
  // We initialize the model asynchronously here, but since it returns a future,
  // we might want to just call initModel() immediately and wait for it.
  // In a real app, you might use a FutureProvider to show a loading state 
  // while the model loads.
  service.initModel();
  
  return service;
});
