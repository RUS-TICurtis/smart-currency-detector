import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/models/detection_session.dart';
import '../../../core/models/ghana_cedi_denomination.dart';
import '../../../core/models/session_item.dart';
import 'history_provider.dart';

// State to hold the current active scan session's items, total, and breakdown.
class SessionState {
  final List<SessionItem> items;
  final double totalValue;
  final int totalNotes;
  final Map<GhanaCedi, int> denominationCounts;

  const SessionState({
    this.items = const [],
    this.totalValue = 0.0,
    this.totalNotes = 0,
    this.denominationCounts = const {},
  });

  SessionItem? get lastAddedItem => items.isNotEmpty ? items.last : null;

  SessionState copyWith({
    List<SessionItem>? items,
    double? totalValue,
    int? totalNotes,
    Map<GhanaCedi, int>? denominationCounts,
  }) {
    return SessionState(
      items: items ?? this.items,
      totalValue: totalValue ?? this.totalValue,
      totalNotes: totalNotes ?? this.totalNotes,
      denominationCounts: denominationCounts ?? this.denominationCounts,
    );
  }
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    return const SessionState();
  }

  /// Add detected items from a scan event into the active session stack.
  /// Returns the newly created list of [SessionItem]s added.
  List<SessionItem> addDetections(Map<GhanaCedi, int> counts, {double? confidence}) {
    if (counts.isEmpty) return [];

    final now = DateTime.now();
    final newItems = <SessionItem>[];

    counts.forEach((denomination, count) {
      final item = SessionItem(
        id: const Uuid().v4(),
        denomination: denomination,
        count: count,
        timestamp: now,
        confidence: confidence,
      );
      newItems.add(item);
    });

    final updatedItems = List<SessionItem>.from(state.items)..addAll(newItems);
    _recalculateState(updatedItems);

    return newItems;
  }

  /// Remove only the most recently added [SessionItem] from the active session.
  /// Returns the removed [SessionItem] if successful, or null if the session is empty.
  SessionItem? removeLastItem() {
    if (state.items.isEmpty) return null;

    final updatedItems = List<SessionItem>.from(state.items);
    final removedItem = updatedItems.removeLast();
    _recalculateState(updatedItems);

    return removedItem;
  }

  /// Reset the active session and clear all items.
  void clearSession() {
    state = const SessionState();
  }

  /// Internal helper to recompute total value, item counts, and denomination breakdown.
  void _recalculateState(List<SessionItem> items) {
    double totalVal = 0.0;
    int totalCount = 0;
    final Map<GhanaCedi, int> breakdown = {};

    for (final item in items) {
      totalVal += item.totalValue;
      totalCount += item.count;
      breakdown[item.denomination] = (breakdown[item.denomination] ?? 0) + item.count;
    }

    state = SessionState(
      items: items,
      totalValue: totalVal,
      totalNotes: totalCount,
      denominationCounts: breakdown,
    );
  }

  Future<void> saveSessionToHistory() async {
    if (state.items.isEmpty) return;

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
