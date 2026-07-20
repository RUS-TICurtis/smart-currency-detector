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
  // Tracking the last added detection to prevent duplicate spam.
  Map<GhanaCedi, int> _lastAddedDetection = {};
  Timer? _cooldownTimer;
  
  // A cooldown duration before the same note configuration can be added again.
  static const Duration _cooldownDuration = Duration(seconds: 3);

  @override
  SessionState build() {
    return const SessionState();
  }

  /// Process stable detections from the camera.
  /// Only adds to the running total if the detected notes have changed
  /// since the last addition, or if the cooldown has expired.
  /// Returns the added value if anything was added, otherwise 0.
  double processDetection(Map<GhanaCedi, int> stableCounts) {
    if (stableCounts.isEmpty) return 0.0;

    // Check if stableCounts is exactly the same or a subset of the last added detection.
    // E.g., if we just added 2x GHS 10, we don't want to add 2x GHS 10 again until cooldown,
    // nor do we want to add 1x GHS 10 (likely just one of the notes became obscured).
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

    // Also check if there's a completely new denomination not in the last detection
    for (final denom in stableCounts.keys) {
      if (!_lastAddedDetection.containsKey(denom)) {
        isNewDetection = true;
        break;
      }
    }

    if (!isNewDetection && _cooldownTimer != null && _cooldownTimer!.isActive) {
      // It's the same or lesser detection, and we're in cooldown. Ignore.
      return 0.0;
    }

    // It's a new detection, OR cooldown expired. Add it.
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

    // Update tracking and reset cooldown timer
    _lastAddedDetection = Map.from(stableCounts);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(_cooldownDuration, () {
      // Once cooldown is over, user can scan the exact same notes again.
      _lastAddedDetection.clear();
    });

    return addedValue;
  }

  void resetScannerTracking() {
    // If the camera explicitly sees NO notes for a few frames, we can reset the tracking early.
    _lastAddedDetection.clear();
    _cooldownTimer?.cancel();
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
