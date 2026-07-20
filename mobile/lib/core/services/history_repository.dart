import 'package:hive_flutter/hive_flutter.dart';
import '../models/detection_session.dart';

class HistoryRepository {
  static const String boxName = 'detection_history';

  // Make sure to call this during app initialization
  static Future<void> init() async {
    Hive.registerAdapter(DetectionSessionAdapter());
    await Hive.openBox<DetectionSession>(boxName);
  }

  Box<DetectionSession> get _box => Hive.box<DetectionSession>(boxName);

  List<DetectionSession> getAllSessions() {
    // Return sessions sorted by timestamp descending (newest first)
    final sessions = _box.values.toList();
    sessions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sessions;
  }

  Future<void> saveSession(DetectionSession session) async {
    await _box.put(session.id, session);
  }

  Future<void> deleteSession(String id) async {
    await _box.delete(id);
  }

  Future<void> clearHistory() async {
    await _box.clear();
  }
}
