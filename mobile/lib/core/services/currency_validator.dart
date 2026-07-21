import 'package:flutter/foundation.dart';
import '../models/ghana_cedi_denomination.dart';
import 'ai_model_service.dart';

class CurrencyValidator {
  /// Maximum note duplicates per denomination per frame (prevents hallucinated stacks).
  static const int maxNotesPerDetection = 5;

  /// Maximum coin duplicates per denomination per frame (coins are smaller, more can be visible).
  static const int maxCoinsPerDetection = 15;

  /// Validates a list of raw predictions from the AI model.
  /// Converts them into a sanitized map of [GhanaCedi] to their validated counts.
  static Map<GhanaCedi, int> validateAndCapDetections(List<RecognizedObject> rawDetections) {
    final Map<GhanaCedi, int> validatedCounts = {};
    int rejectedCount = 0;

    for (final detection in rawDetections) {
      final denomination = GhanaCedi.fromString(detection.label);
      if (denomination == null) {
        rejectedCount++;
        continue;
      }

      final currentCount = validatedCounts[denomination] ?? 0;
      
      // Coins are physically smaller; we cap them at maxCoinsPerDetection.
      // Notes are larger; cap at maxNotesPerDetection to prevent hallucinated duplicates.
      final maxAllowed = denomination.value < 1.0 ? maxCoinsPerDetection : maxNotesPerDetection;

      if (currentCount < maxAllowed) {
        validatedCounts[denomination] = currentCount + 1;
      } else {
        // We hit the cap. Ignore this duplicate bounding box to prevent hallucinated aggregation.
        rejectedCount++;
      }
    }

    if (kDebugMode && rejectedCount > 0) {
      debugPrint('CurrencyValidator: Rejected/Capped $rejectedCount overlapping or invalid bounding boxes.');
    }

    return validatedCounts;
  }
}
