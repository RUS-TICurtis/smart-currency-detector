enum GhanaCedi {
  pesewa10(0.10, isCoin: true),
  pesewa20(0.20, isCoin: true),
  pesewa50(0.50, isCoin: true),
  ghs1Coin(1.0, isCoin: true),
  ghs1Note(1.0, isCoin: false),
  ghs2Coin(2.0, isCoin: true),
  ghs2Note(2.0, isCoin: false),
  ghs5(5.0, isCoin: false),
  ghs10(10.0, isCoin: false),
  ghs20(20.0, isCoin: false),
  ghs50(50.0, isCoin: false),
  ghs100(100.0, isCoin: false),
  ghs200(200.0, isCoin: false);

  final double value;
  final bool isCoin;

  const GhanaCedi(this.value, {required this.isCoin});

  /// Indicates whether this item is a "coin" or a "note".
  String get itemType => isCoin ? 'coin' : 'note';

  /// Safely parse a raw string label into a validated Enum.
  static GhanaCedi? fromString(String label) {
    final lowerLabel = label.toLowerCase();
    
    // Explicit label matching
    switch (lowerLabel) {
      case '100_cedi':
        return GhanaCedi.ghs100;
      case '10_cedi':
        return GhanaCedi.ghs10;
      case '10_pesewas_coin':
        return GhanaCedi.pesewa10;
      case '1_cedi':
        return GhanaCedi.ghs1Note;
      case '1_cedi_coin':
        return GhanaCedi.ghs1Coin;
      case '200_cedi':
        return GhanaCedi.ghs200;
      case '20_cedi':
        return GhanaCedi.ghs20;
      case '20_pesewas_coin':
        return GhanaCedi.pesewa20;
      case '2_cedi':
        return GhanaCedi.ghs2Note;
      case '2_cedi_coin':
        return GhanaCedi.ghs2Coin;
      case '50_cedi':
        return GhanaCedi.ghs50;
      case '50_pesewas_coin':
        return GhanaCedi.pesewa50;
      case '5_cedi':
        return GhanaCedi.ghs5;
    }

    // Dynamic heuristic fallback
    final match = RegExp(r'\d+').firstMatch(label);
    if (match == null) return null;
    
    final number = double.tryParse(match.group(0)!);
    if (number == null) return null;

    final isPesewa = lowerLabel.contains('pesewa');
    final checkCoin = lowerLabel.contains('coin') || isPesewa;
    final actualValue = isPesewa ? (number / 100.0) : number;

    for (final note in GhanaCedi.values) {
      if ((note.value - actualValue).abs() < 0.001 && note.isCoin == checkCoin) {
        return note;
      }
    }
    return null; // Reject unknown
  }

  String get displayName {
    if (value < 1.0) {
      return '${(value * 100).toInt()} Pesewas coin';
    }
    final unit = isCoin ? 'coin' : 'note';
    return '${value.toInt()} Cedi $unit';
  }

  /// Formats a double value into spoken English words (e.g. 130.0 -> "One Hundred and Thirty Ghana Cedis").
  static String formatSpokenTotal(double total) {
    if (total <= 0) return 'Zero Ghana Cedis';

    final cediPart = total.floor();
    final pesewaPart = ((total - cediPart) * 100).round();

    final parts = <String>[];

    if (cediPart > 0) {
      final words = _numberToWords(cediPart);
      final unit = cediPart == 1 ? 'Ghana Cedi' : 'Ghana Cedis';
      parts.add('$words $unit');
    }

    if (pesewaPart > 0) {
      final words = _numberToWords(pesewaPart);
      parts.add('$words Pesewas');
    }

    return parts.join(' and ');
  }

  static String _numberToWords(int number) {
    if (number == 0) return 'Zero';

    final units = [
      '',
      'One',
      'Two',
      'Three',
      'Four',
      'Five',
      'Six',
      'Seven',
      'Eight',
      'Nine',
      'Ten',
      'Eleven',
      'Twelve',
      'Thirteen',
      'Fourteen',
      'Fifteen',
      'Sixteen',
      'Seventeen',
      'Eighteen',
      'Nineteen',
    ];

    final tens = [
      '',
      '',
      'Twenty',
      'Thirty',
      'Forty',
      'Fifty',
      'Sixty',
      'Seventy',
      'Eighty',
      'Ninety',
    ];

    if (number < 20) {
      return units[number];
    }

    if (number < 100) {
      final t = number ~/ 10;
      final u = number % 10;
      return u == 0 ? tens[t] : '${tens[t]} ${units[u]}';
    }

    if (number < 1000) {
      final h = number ~/ 100;
      final rem = number % 100;
      if (rem == 0) {
        return '${units[h]} Hundred';
      }
      return '${units[h]} Hundred and ${_numberToWords(rem)}';
    }

    return number.toString();
  }
}
