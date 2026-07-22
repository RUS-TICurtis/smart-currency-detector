import 'ghana_cedi_denomination.dart';

/// Represents an individual scanned currency item in an active session.
class SessionItem {
  final String id;
  final GhanaCedi denomination;
  final int count;
  final DateTime timestamp;
  final double? confidence;

  const SessionItem({
    required this.id,
    required this.denomination,
    this.count = 1,
    required this.timestamp,
    this.confidence,
  });

  /// Total value for this specific item entry.
  double get totalValue => denomination.value * count;

  /// Verbal description of this item entry (e.g. "Five Ghana Cedis" or "Ten Pesewas").
  String get spokenValue {
    if (denomination.value < 1.0) {
      final pesewas = (denomination.value * 100 * count).toInt();
      return '$pesewas Pesewas';
    }
    final totalCedi = (denomination.value * count).toInt();
    final unit = totalCedi == 1 ? 'Cedi' : 'Cedis';
    return '$totalCedi Ghana $unit';
  }
}
