import 'package:flutter_test/flutter_test.dart';
import 'package:cedi_cam/core/models/ghana_cedi_denomination.dart';
import 'package:cedi_cam/core/services/currency_validator.dart';
import 'package:cedi_cam/core/services/ai_model_service.dart';

void main() {
  group('GhanaCedi Denomination & Coin/Note Distinction Tests', () {
    test('Parses coins correctly and marks them as isCoin=true', () {
      final c10p = GhanaCedi.fromString('10_pesewas_coin');
      expect(c10p, equals(GhanaCedi.pesewa10));
      expect(c10p?.isCoin, isTrue);
      expect(c10p?.itemType, equals('coin'));

      final c1g = GhanaCedi.fromString('1_cedi_coin');
      expect(c1g, equals(GhanaCedi.ghs1Coin));
      expect(c1g?.isCoin, isTrue);
      expect(c1g?.itemType, equals('coin'));

      final c2g = GhanaCedi.fromString('2_cedi_coin');
      expect(c2g, equals(GhanaCedi.ghs2Coin));
      expect(c2g?.isCoin, isTrue);
      expect(c2g?.itemType, equals('coin'));
    });

    test('Parses notes correctly and marks them as isCoin=false', () {
      final n1g = GhanaCedi.fromString('1_cedi');
      expect(n1g, equals(GhanaCedi.ghs1Note));
      expect(n1g?.isCoin, isFalse);
      expect(n1g?.itemType, equals('note'));

      final n2g = GhanaCedi.fromString('2_cedi');
      expect(n2g, equals(GhanaCedi.ghs2Note));
      expect(n2g?.isCoin, isFalse);
      expect(n2g?.itemType, equals('note'));

      final n50g = GhanaCedi.fromString('50_cedi');
      expect(n50g, equals(GhanaCedi.ghs50));
      expect(n50g?.isCoin, isFalse);
      expect(n50g?.itemType, equals('note'));
    });

    test('Validator caps coins up to maxCoinsPerDetection and notes up to maxNotesPerDetection', () {
      final rawCoins = List.generate(20, (_) => RecognizedObject(0, '1_cedi_coin', 0.9, 0, 0, 10, 10));
      final validatedCoins = CurrencyValidator.validateAndCapDetections(rawCoins);
      expect(validatedCoins[GhanaCedi.ghs1Coin], equals(CurrencyValidator.maxCoinsPerDetection));

      final rawNotes = List.generate(10, (_) => RecognizedObject(0, '1_cedi', 0.9, 0, 0, 10, 10));
      final validatedNotes = CurrencyValidator.validateAndCapDetections(rawNotes);
      expect(validatedNotes[GhanaCedi.ghs1Note], equals(CurrencyValidator.maxNotesPerDetection));
    });
  });
}
