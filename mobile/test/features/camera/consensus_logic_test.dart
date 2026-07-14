import 'package:flutter_test/flutter_test.dart';

Map<String, int> getMedianConsensus(List<Map<String, int>> history) {
  if (history.length < 5) return {};

  final Map<String, int> stableCounts = {};
  final Set<String> allLabels = {};
  for (final map in history) {
    allLabels.addAll(map.keys);
  }

  for (final label in allLabels) {
    final labelCounts = history.map((m) => m[label] ?? 0).toList();
    labelCounts.sort();
    final median = labelCounts[2]; // middle element of 5
    if (median > 0) {
      stableCounts[label] = median;
    }
  }
  return stableCounts;
}

void main() {
  group('Sliding Window Median Consensus Logic Tests', () {
    test('Returns empty map when history length is less than 5', () {
      final history = [
        {'10 GHS': 2},
        {'10 GHS': 2},
      ];
      expect(getMedianConsensus(history).isEmpty, isTrue);
    });

    test('Correctly calculates median for stable detections', () {
      final history = [
        {'10 GHS': 2},
        {'10 GHS': 2},
        {'10 GHS': 2},
        {'10 GHS': 2},
        {'10 GHS': 2},
      ];
      final result = getMedianConsensus(history);
      expect(result['10 GHS'], 2);
    });

    test('Ignores outliers using median', () {
      final history = [
        {'10 GHS': 5}, // outlier
        {'10 GHS': 2},
        {'10 GHS': 2},
        {'10 GHS': 0}, // outlier (dropped)
        {'10 GHS': 2},
      ];
      final result = getMedianConsensus(history);
      expect(result['10 GHS'], 2);
    });

    test('Handles multiple independent denominations', () {
      final history = [
        {'10 GHS': 3, '20 GHS': 1},
        {'10 GHS': 3, '20 GHS': 2}, // saw extra 20
        {'10 GHS': 2, '20 GHS': 1}, // missed a 10
        {'10 GHS': 3, '20 GHS': 1},
        {'10 GHS': 3, '50 GHS': 1}, // saw a false 50
      ];
      
      final result = getMedianConsensus(history);
      // For 10 GHS: [2, 3, 3, 3, 3] -> median is 3
      // For 20 GHS: [0, 1, 1, 1, 2] -> median is 1
      // For 50 GHS: [0, 0, 0, 0, 1] -> median is 0
      
      expect(result['10 GHS'], 3);
      expect(result['20 GHS'], 1);
      expect(result.containsKey('50 GHS'), isFalse);
    });
  });
}
