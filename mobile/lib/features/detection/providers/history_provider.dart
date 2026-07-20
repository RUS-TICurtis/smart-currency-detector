import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/history_repository.dart';
import '../../../core/models/detection_session.dart';

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return HistoryRepository();
});

class HistoryNotifier extends Notifier<List<DetectionSession>> {
  @override
  List<DetectionSession> build() {
    final repo = ref.watch(historyRepositoryProvider);
    return repo.getAllSessions();
  }

  Future<void> addSession(DetectionSession session) async {
    final repo = ref.read(historyRepositoryProvider);
    await repo.saveSession(session);
    state = repo.getAllSessions();
  }

  Future<void> deleteSession(String id) async {
    final repo = ref.read(historyRepositoryProvider);
    await repo.deleteSession(id);
    state = repo.getAllSessions();
  }

  Future<void> clearHistory() async {
    final repo = ref.read(historyRepositoryProvider);
    await repo.clearHistory();
    state = repo.getAllSessions();
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<DetectionSession>>(() {
  return HistoryNotifier();
});
