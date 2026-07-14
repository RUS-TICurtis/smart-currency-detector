import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../core/services/ai_model_service.dart';

class BoundingBoxOverlay extends StatelessWidget {
  final CameraController cameraController;
  final List<RecognizedObject> detections;
  final double modelInputSize;

  const BoundingBoxOverlay({
    super.key,
    required this.cameraController,
    required this.detections,
    this.modelInputSize = 640.0,
  });

  @override
  Widget build(BuildContext context) {
    if (!cameraController.value.isInitialized) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = cameraController.value.previewSize;
        if (previewSize == null) return const SizedBox.shrink();

        // Calculate aspect ratio. CameraPreview rotates depending on orientation.
        final bool isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        
        // previewSize is usually expressed in landscape (e.g., 1920x1080)
        // so we need to swap width and height if we are in portrait mode.
        final double videoWidth =
            isLandscape ? previewSize.width : previewSize.height;
        final double videoHeight =
            isLandscape ? previewSize.height : previewSize.width;

        // Apply BoxFit.cover (which is what CameraPreview normally does if constrained)
        // Wait, CameraPreview is typically wrapped in a Center without constraints, which acts as BoxFit.contain 
        // OR it's forced to full screen. Let's assume the stack position fills screen and it's center-cropped (BoxFit.cover) or contained.
        // Actually CameraPreview inside a Container(color: Colors.black, child: Center(child: CameraPreview())) 
        // acts as BoxFit.contain. Let's use contain.
        final FittedSizes fittedSizes = applyBoxFit(
          BoxFit.contain,
          Size(videoWidth, videoHeight),
          Size(constraints.maxWidth, constraints.maxHeight),
        );

        final Rect renderRect = Alignment.center.inscribe(
          fittedSizes.destination,
          Rect.fromLTWH(0, 0, constraints.maxWidth, constraints.maxHeight),
        );

        return CustomPaint(
          painter: _BoundingBoxPainter(
            detections: detections,
            modelInputSize: modelInputSize,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
            renderRect: renderRect,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  final List<RecognizedObject> detections;
  final double modelInputSize;
  final double videoWidth;
  final double videoHeight;
  final Rect renderRect;

  _BoundingBoxPainter({
    required this.detections,
    required this.modelInputSize,
    required this.videoWidth,
    required this.videoHeight,
    required this.renderRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    // The image was scaled and letterboxed into 640x640 in AIModelService.
    final scaleX = modelInputSize / videoWidth;
    final scaleY = modelInputSize / videoHeight;
    final scale = min(scaleX, scaleY);

    final targetW = videoWidth * scale;
    final targetH = videoHeight * scale;

    final dx = (modelInputSize - targetW) / 2;
    final dy = (modelInputSize - targetH) / 2;

    // Render scaling (from video space to screen space)
    final renderScaleX = renderRect.width / videoWidth;
    final renderScaleY = renderRect.height / videoHeight;

    for (final detection in detections) {
      // Map back to original video space
      final origX1 = (detection.x1 - dx) / scale;
      final origY1 = (detection.y1 - dy) / scale;
      final origX2 = (detection.x2 - dx) / scale;
      final origY2 = (detection.y2 - dy) / scale;

      // Map to screen render space
      final screenX1 = renderRect.left + origX1 * renderScaleX;
      final screenY1 = renderRect.top + origY1 * renderScaleY;
      final screenX2 = renderRect.left + origX2 * renderScaleX;
      final screenY2 = renderRect.top + origY2 * renderScaleY;

      final rect = Rect.fromLTRB(screenX1, screenY1, screenX2, screenY2);

      // Pick a color based on the label hash for visual distinction
      final color = Colors.primaries[detection.label.hashCode % Colors.primaries.length];

      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawRect(rect, paint);

      // Draw label background
      final bgPaint = Paint()..color = color.withValues(alpha: 0.7);
      
      final textSpan = TextSpan(
        text: '${detection.label} ${(detection.confidence * 100).toStringAsFixed(1)}%',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - textPainter.height - 4,
        textPainter.width + 8,
        textPainter.height + 4,
      );

      // Clamp label to screen
      double dxAdjust = 0;
      double dyAdjust = 0;
      if (labelRect.top < 0) dyAdjust = -labelRect.top;
      if (labelRect.left < 0) dxAdjust = -labelRect.left;

      canvas.drawRect(labelRect.shift(Offset(dxAdjust, dyAdjust)), bgPaint);
      
      textPainter.paint(
        canvas,
        Offset(rect.left + 4 + dxAdjust, rect.top - textPainter.height - 2 + dyAdjust),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.renderRect != renderRect;
  }
}
