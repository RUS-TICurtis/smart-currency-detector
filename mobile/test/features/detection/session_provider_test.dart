import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cedi_cam/core/models/ghana_cedi_denomination.dart';
import 'package:cedi_cam/features/detection/providers/session_provider.dart';

void main() {
  group('Session-Based Accumulation & State Machine Unit Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial session state is empty with 0 total', () {
      final state = container.read(sessionProvider);
      expect(state.items, isEmpty);
      expect(state.totalValue, equals(0.0));
      expect(state.totalNotes, equals(0));
      expect(state.lastAddedItem, isNull);
    });

    test('Adding detections pushes SessionItem to stack and updates totals', () {
      final notifier = container.read(sessionProvider.notifier);

      final added = notifier.addDetections({GhanaCedi.ghs20: 1});
      expect(added.length, equals(1));
      expect(added.first.denomination, equals(GhanaCedi.ghs20));
      expect(added.first.spokenValue, equals('20 Ghana Cedis'));

      final state = container.read(sessionProvider);
      expect(state.items.length, equals(1));
      expect(state.totalValue, equals(20.0));

      // Add a second note (GHS 50)
      notifier.addDetections({GhanaCedi.ghs50: 1});
      final state2 = container.read(sessionProvider);
      expect(state2.items.length, equals(2));
      expect(state2.totalValue, equals(70.0));
      expect(state2.lastAddedItem?.denomination, equals(GhanaCedi.ghs50));
    });

    test('removeLastItem removes only the most recent currency and recalculates total', () {
      final notifier = container.read(sessionProvider.notifier);

      notifier.addDetections({GhanaCedi.ghs20: 1});
      notifier.addDetections({GhanaCedi.ghs10: 1});
      notifier.addDetections({GhanaCedi.ghs5: 1});

      var state = container.read(sessionProvider);
      expect(state.totalValue, equals(35.0));
      expect(state.items.length, equals(3));

      // Clear (remove last item: GHS 5)
      final removed = notifier.removeLastItem();
      expect(removed, isNotNull);
      expect(removed?.denomination, equals(GhanaCedi.ghs5));
      expect(removed?.spokenValue, equals('5 Ghana Cedis'));

      state = container.read(sessionProvider);
      expect(state.items.length, equals(2));
      expect(state.totalValue, equals(30.0));
      expect(state.lastAddedItem?.denomination, equals(GhanaCedi.ghs10));
    });

    test('removeLastItem on empty session returns null', () {
      final notifier = container.read(sessionProvider.notifier);
      final removed = notifier.removeLastItem();
      expect(removed, isNull);
    });

    test('Spoken number words format accurately for Sum calculations', () {
      expect(GhanaCedi.formatSpokenTotal(5.0), equals('Five Ghana Cedis'));
      expect(GhanaCedi.formatSpokenTotal(20.0), equals('Twenty Ghana Cedis'));
      expect(GhanaCedi.formatSpokenTotal(50.0), equals('Fifty Ghana Cedis'));
      expect(GhanaCedi.formatSpokenTotal(95.0), equals('Ninety Five Ghana Cedis'));
      expect(GhanaCedi.formatSpokenTotal(130.0), equals('One Hundred and Thirty Ghana Cedis'));
      expect(GhanaCedi.formatSpokenTotal(200.0), equals('Two Hundred Ghana Cedis'));
      expect(GhanaCedi.formatSpokenTotal(0.50), equals('Fifty Pesewas'));
    });
  });
}
