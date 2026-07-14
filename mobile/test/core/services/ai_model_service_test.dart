import 'package:flutter_test/flutter_test.dart';
import 'package:cedi_cam/core/services/ai_model_service.dart';

void main() {
  group('AIModelService NMS and IoU Tests', () {
    test('IoU calculates correctly for non-overlapping boxes', () {
      final box1 = RecognizedObject(0, '10 GHS', 0.9, 0, 0, 10, 10);
      final box2 = RecognizedObject(0, '10 GHS', 0.9, 20, 20, 30, 30);
      
      final iou = AIModelService.iou(box1, box2);
      expect(iou, 0.0);
    });

    test('IoU calculates correctly for identical boxes', () {
      final box1 = RecognizedObject(0, '10 GHS', 0.9, 0, 0, 10, 10);
      final box2 = RecognizedObject(0, '10 GHS', 0.9, 0, 0, 10, 10);
      
      final iou = AIModelService.iou(box1, box2);
      expect(iou, 1.0);
    });

    test('IoU calculates correctly for partially overlapping boxes', () {
      final box1 = RecognizedObject(0, '10 GHS', 0.9, 0, 0, 10, 10); // Area 100
      final box2 = RecognizedObject(0, '10 GHS', 0.9, 5, 0, 15, 10); // Area 100
      
      // Intersection is from x=5 to x=10, y=0 to y=10 => width 5, height 10 => area 50
      // Union = 100 + 100 - 50 = 150
      // IoU = 50 / 150 = 1/3 (approx 0.333)
      final iou = AIModelService.iou(box1, box2);
      expect(iou, closeTo(0.3333, 0.001));
    });

    test('applyNMS suppresses highly overlapping boxes', () {
      final detections = [
        RecognizedObject(0, '10 GHS', 0.95, 0, 0, 10, 10),
        RecognizedObject(0, '10 GHS', 0.90, 1, 1, 9, 9), // highly overlapping
        RecognizedObject(1, '20 GHS', 0.85, 50, 50, 60, 60), // far away
      ];

      final kept = AIModelService.applyNMS(detections, 0.45);
      
      expect(kept.length, 2);
      // The box with higher confidence should be kept
      expect(kept[0].confidence, 0.95);
      expect(kept[1].confidence, 0.85);
    });
  });
}
