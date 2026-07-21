import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/ghana_cedi_denomination.dart';
import '../../../core/models/detection_session.dart';
import 'history_provider.dart';
import 'package:uuid/uuid.dart';

// State to hold the current session's running total and notes.
class SessionState {
  final double totalValue;
  final int totalNotes;
  final Map<GhanaCedi, int> denominationCounts;

  const SessionState({
    this.totalValue = 0.0,
    this.totalNotes = 0,
    this.denominationCounts = const {},
  });

  SessionState copyWith({
    double? totalValue,
    int? totalNotes,
    Map<GhanaCedi, int>? denominationCounts,
  }) {
    return SessionState(
      totalValue: totalValue ?? this.totalValue,
      totalNotes: totalNotes ?? this.totalNotes,
      denominationCounts: denominationCounts ?? this.denominationCounts,
    );
  }
}

class SessionNotifier extends Notifier<SessionState> {
  // Tracking the last added detection to prevent duplicate spam until notes/coins exit view.
  Map<GhanaCedi, int> _lastAddedDetection = {};

  @override
  SessionState build() {
    return const SessionState();
  }

  /// Process stable detections from the camera.
  /// Only adds to the running total if new notes/coins have been added
  /// or if scanner tracking was reset (e.g. note removed from camera view).
  /// Returns the added value if anything was added, otherwise 0.
  double processDetection(Map<GhanaCedi, int> stableCounts) {
    if (stableCounts.isEmpty) return 0.0;

    // Check if stableCounts is higher in count or contains a new denomination
    bool isNewDetection = false;
    for (final entry in stableCounts.entries) {
      final denomination = entry.key;
      final count = entry.value;
      final lastCount = _lastAddedDetection[denomination] ?? 0;
      
      if (count > lastCount) {
        isNewDetection = true;
        break;
      }
    }

    for (final denom in stableCounts.keys) {
      if (!_lastAddedDetection.containsKey(denom)) {
        isNewDetection = true;
        break;
      }
    }

    if (!isNewDetection) {
      // The same or a subset of the currently tracked item is still in view.
      return 0.0;
    }

    // It's a new or additional detection. Add it to total.
    double addedValue = 0.0;
    int addedNotes = 0;
    final newCounts = Map<GhanaCedi, int>.from(state.denominationCounts);

    stableCounts.forEach((denomination, count) {
      addedValue += denomination.value * count;
      addedNotes += count;
      newCounts[denomination] = (newCounts[denomination] ?? 0) + count;
    });

    state = state.copyWith(
      totalValue: state.totalValue + addedValue,
      totalNotes: state.totalNotes + addedNotes,
      denominationCounts: newCounts,
    );

    // Update tracking lock until note/coin exits camera view
    _lastAddedDetection = Map.from(stableCounts);

    return addedValue;
  }

  void resetScannerTracking() {
    // Called when camera sees no currency items for several consecutive frames.
    _lastAddedDetection.clear();
  }

  void clearSession() {
    state = const SessionState();
    resetScannerTracking();
  }

  Future<void> saveSessionToHistory() async {
    if (state.totalNotes == 0) return;

    final session = DetectionSession(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      totalValue: state.totalValue,
      totalNotes: state.totalNotes,
      denominationCounts: state.denominationCounts,
    );

    await ref.read(historyProvider.notifier).addSession(session);
    clearSession();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(() {
  return SessionNotifier();
});
