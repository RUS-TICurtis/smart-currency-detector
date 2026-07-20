enum GhanaCedi {
  pesewa10(0.10),
  pesewa20(0.20),
  pesewa50(0.50),
  ghs1(1.0),
  ghs2(2.0),
  ghs5(5.0),
  ghs10(10.0),
  ghs20(20.0),
  ghs50(50.0),
  ghs100(100.0),
  ghs200(200.0);

  final double value;

  const GhanaCedi(this.value);

  /// Safely parse a raw string label (e.g. "100 Cedis" or "10_pesewas_coin") into a validated Enum.
  static GhanaCedi? fromString(String label) {
    final lowerLabel = label.toLowerCase();
    final match = RegExp(r'\d+').firstMatch(label);
    if (match == null) return null;
    
    final number = double.tryParse(match.group(0)!);
    if (number == null) return null;

    final isPesewa = lowerLabel.contains('pesewa');
    final actualValue = isPesewa ? (number / 100.0) : number;

    for (final note in GhanaCedi.values) {
      if ((note.value - actualValue).abs() < 0.001) {
        return note;
      }
    }
    return null; // Reject completely unknown or hallucinated numbers
  }

  String get displayName {
    if (value < 1.0) {
      return '${(value * 100).toInt()} Pesewas';
    }
    return '${value.toInt()} Cedis';
  }
}
