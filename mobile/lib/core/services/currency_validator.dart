import 'package:flutter/foundation.dart';
import '../models/ghana_cedi_denomination.dart';
import 'ai_model_service.dart';

class CurrencyValidator {
  /// The maximum number of identical notes we reasonably expect to see in a single frame.
  /// If the model hallucinates 15 bounding boxes around a single note, this will cap it,
  /// preventing mathematically impossible totals like "1500 Cedis" from a single 100 note.
  static const int maxNotesPerDenomination = 4;

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
      
      // Coins are physically smaller, so we can reasonably expect up to 15 in a single frame.
      // Notes are larger, so we cap them at 5 to prevent duplicate bounding box hallucinations.
      final maxAllowed = denomination.value < 1.0 ? 15 : 5;

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
