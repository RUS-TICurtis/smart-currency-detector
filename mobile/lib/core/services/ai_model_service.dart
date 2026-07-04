import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

// ---------------------------------------------------------------------------
// Inter-isolate data transfer objects
// (CameraImage and its Plane are not sendable across isolates)
// ---------------------------------------------------------------------------

class IsolateCameraImage {
  final int width;
  final int height;
  final String formatGroup;
  final List<IsolatePlane> planes;
  final int sensorOrientation;

  const IsolateCameraImage(
    this.width,
    this.height,
    this.formatGroup,
    this.planes,
    this.sensorOrientation,
  );
}

class IsolatePlane {
  final Uint8List bytes;
  final int bytesPerRow;
  // Non-nullable: caller must resolve null with a sensible default.
  final int bytesPerPixel;

  const IsolatePlane(this.bytes, this.bytesPerRow, this.bytesPerPixel);
}

// ---------------------------------------------------------------------------
// Internal detection result (used during NMS)
// ---------------------------------------------------------------------------

class _Detection {
  final int classIndex;
  final double confidence;
  // Bounding-box corners in pixel space (0..inputSize).
  final double x1, y1, x2, y2;

  const _Detection(
    this.classIndex,
    this.confidence,
    this.x1,
    this.y1,
    this.x2,
    this.y2,
  );
}

// ---------------------------------------------------------------------------
// AIModelService
// ---------------------------------------------------------------------------

class AIModelService {
  Interpreter? _interpreter;
  List<String>? _labels;

  static const String _modelPath = 'assets/model/best.tflite';
  static const String _labelPath = 'assets/model/labels.txt';

  /// Input spatial dimension expected by the YOLOv11 model (640 × 640).
  static const int inputSize = 640;

  /// Gray letterbox fill value — matches YOLOv5 / v8 / v11 training default.
  static const double _letterboxFill = 114.0 / 255.0;

  /// IoU threshold for Non-Maximum Suppression.
  static const double _nmsIouThreshold = 0.45;

  bool _isReady = false;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Load the TFLite model and labels from app assets.
  /// Must be awaited before calling [predict] or [predictFromCameraImage].
  Future<void> initModel() async {
    final options = InterpreterOptions();

    // ── GPU / NPU acceleration (best-effort; falls back to CPU) ──
    // tflite_flutter exposes delegates via the options.useNnApiForAndroid
    // shorthand and the GpuDelegateV2 helper.  Both are wrapped in try/catch
    // because delegate availability depends on device and OS version.
    try {
      if (Platform.isAndroid) {
        options.useNnApiForAndroid = true;
        debugPrint('AIModelService: NNAPI delegate requested.');
      } else if (Platform.isIOS) {
        options.addDelegate(GpuDelegateV2());
        debugPrint('AIModelService: Metal/GPU delegate enabled.');
      }
    } catch (e) {
      debugPrint('AIModelService: GPU delegate unavailable, using CPU. ($e)');
    }

    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

    final rawLabels = await rootBundle.loadString(_labelPath);
    _labels = rawLabels
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // ── Sanity check: label count must match model output classes ──
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    debugPrint('AIModelService: output tensor shape = $outputShape');
    // YOLOv11 raw output: [1, 4+numClasses, numAnchors]
    if (outputShape.length >= 2) {
      final modelClasses = outputShape[1] - 4;
      if (modelClasses != _labels!.length) {
        debugPrint(
          'AIModelService WARNING: labels.txt has ${_labels!.length} classes '
          'but model reports $modelClasses classes. '
          'Verify labels.txt ordering against data.yaml.',
        );
      }
    }

    debugPrint('AIModelService: loaded ${_labels!.length} labels: $_labels');
    _isReady = true;
  }

  /// Returns true once [initModel] has completed successfully.
  bool get isReady => _isReady;

  // ---------------------------------------------------------------------------
  // Public inference API
  // ---------------------------------------------------------------------------

  /// Run inference on a still image at [imagePath] (gallery / takePicture).
  Future<String?> predict(String imagePath, double confidenceThreshold) async {
    if (!_isReady) return null;
    try {
      // Preprocessing is CPU-heavy — offload to a background isolate.
      // Float32List is a TypedData and transfers efficiently across isolates.
      final input = await Isolate.run(
        () => _preprocessImageToFloat32(imagePath, inputSize),
      );
      if (input == null) return null;
      return _runInference(input, confidenceThreshold);
    } catch (e) {
      debugPrint('AIModelService: gallery inference error: $e');
      return null;
    }
  }

  /// Run inference on a live [CameraImage] frame from the camera stream.
  Future<String?> predictFromCameraImage(
    CameraImage image,
    int sensorOrientation,
    double confidenceThreshold,
  ) async {
    if (!_isReady) return null;
    try {
      // Serialise plane data for isolate transfer.
      // FIX (C-05): default bytesPerPixel to 2 for Android NV12/NV21 UV planes.
      final planes = image.planes
          .map(
            (p) => IsolatePlane(p.bytes, p.bytesPerRow, p.bytesPerPixel ?? 2),
          )
          .toList();

      final isolateData = IsolateCameraImage(
        image.width,
        image.height,
        image.format.group.name,
        planes,
        sensorOrientation,
      );

      // FIX (C-06): return a compact Float32List instead of
      // List<List<List<List<double>>>> to avoid ~31 MB isolate serialisation.
      final input = await Isolate.run(
        () => _preprocessCameraImageToFloat32(isolateData, inputSize),
      );
      if (input == null) return null;
      return _runInference(input, confidenceThreshold);
    } catch (e) {
      debugPrint('AIModelService: camera inference error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Inference core (runs on main isolate — interpreter lives here)
  // ---------------------------------------------------------------------------

  /// FIX (C-01 / H-09): Parse the raw YOLOv11 output with proper NMS instead
  /// of naively picking the single highest-confidence anchor.
  String? _runInference(Float32List flatInput, double confidenceThreshold) {
    // ── Reshape 1D flat buffer to 4D nested list [1, 3, 640, 640] ──
    // We transfer a flat Float32List across isolates for speed, but tflite_flutter
    // expects a nested list matching the tensor shape, otherwise it resizes the
    // model's input tensor to 1D and breaks internal operations like TRANSPOSE.
    final input4D = _reshapeTo4D(flatInput, inputSize);

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    // Expected YOLOv11 raw output: [1, 4+numClasses, numAnchors]
    final int numRows = outputShape[1];
    final int numAnchors = outputShape[2];
    final int numClasses = numRows - 4;

    // Allocate the output buffer that tflite_flutter will write into.
    final output = List.generate(
      1,
      (_) =>
          List.generate(numRows, (_) => List<double>.filled(numAnchors, 0.0)),
    );

    _interpreter!.run(input4D, output);

    // ── 1. Parse raw anchors into candidate detections ──
    final detections = <_Detection>[];

    for (int a = 0; a < numAnchors; a++) {
      double maxScore = 0.0;
      int bestClass = -1;

      for (int c = 0; c < numClasses; c++) {
        final score = output[0][4 + c][a];
        if (score > maxScore) {
          maxScore = score;
          bestClass = c;
        }
      }

      // Skip low-confidence anchors before NMS for performance.
      if (maxScore < confidenceThreshold) continue;
      if (bestClass < 0 || bestClass >= (_labels?.length ?? 0)) continue;

      // YOLOv11 box format: cx, cy, w, h in pixel space (0..inputSize).
      final cx = output[0][0][a];
      final cy = output[0][1][a];
      final w = output[0][2][a];
      final h = output[0][3][a];

      detections.add(
        _Detection(
          bestClass,
          maxScore,
          cx - w / 2, // x1
          cy - h / 2, // y1
          cx + w / 2, // x2
          cy + h / 2, // y2
        ),
      );
    }

    if (detections.isEmpty) return null;

    // ── 2. Apply Non-Maximum Suppression ──
    final kept = _applyNMS(detections, _nmsIouThreshold);
    if (kept.isEmpty) return null;

    // ── 3. Return the label of the highest-confidence surviving detection ──
    kept.sort((a, b) => b.confidence.compareTo(a.confidence));
    final winner = kept.first;
    debugPrint(
      'AIModelService: detected "${_labels![winner.classIndex]}" '
      '(confidence ${winner.confidence.toStringAsFixed(3)})',
    );
    return _labels![winner.classIndex];
  }

  // ---------------------------------------------------------------------------
  // Non-Maximum Suppression
  // ---------------------------------------------------------------------------

  static List<_Detection> _applyNMS(
    List<_Detection> detections,
    double iouThreshold,
  ) {
    // Sort descending by confidence so higher-quality boxes win.
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    final suppressed = List<bool>.filled(detections.length, false);
    final kept = <_Detection>[];

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;
      kept.add(detections[i]);
      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;
        if (_iou(detections[i], detections[j]) > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return kept;
  }

  static double _iou(_Detection a, _Detection b) {
    final interX1 = max(a.x1, b.x1);
    final interY1 = max(a.y1, b.y1);
    final interX2 = min(a.x2, b.x2);
    final interY2 = min(a.y2, b.y2);

    final interW = max(0.0, interX2 - interX1);
    final interH = max(0.0, interY2 - interY1);
    final interArea = interW * interH;

    final areaA = (a.x2 - a.x1) * (a.y2 - a.y1);
    final areaB = (b.x2 - b.x1) * (b.y2 - b.y1);
    final unionArea = areaA + areaB - interArea;

    return unionArea <= 0 ? 0.0 : interArea / unionArea;
  }

  // ---------------------------------------------------------------------------
  // Static preprocessing helpers
  // (static = safe to call inside Isolate.run)
  // ---------------------------------------------------------------------------

  /// Reshapes a flat CHW Float32List back into a 4D nested list structure
  /// `[1][3][height][width]` required by tflite_flutter.
  static List<List<List<List<double>>>> _reshapeTo4D(
    Float32List buffer,
    int inputSize,
  ) {
    return List.generate(
      1,
      (_) => List.generate(
        3,
        (c) => List.generate(inputSize, (y) {
          final row = List<double>.filled(inputSize, 0.0);
          final base = c * inputSize * inputSize + y * inputSize;
          for (int x = 0; x < inputSize; x++) {
            row[x] = buffer[base + x];
          }
          return row;
        }),
      ),
    );
  }

  /// Preprocess a gallery image file into a [Float32List] ready for inference.
  static Float32List? _preprocessImageToFloat32(
    String imagePath,
    int inputSize,
  ) {
    try {
      final bytes = File(imagePath).readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      return _resizeAndLetterbox(image, inputSize);
    } catch (e) {
      return null;
    }
  }

  /// Preprocess a camera frame into a [Float32List] ready for inference.
  static Float32List? _preprocessCameraImageToFloat32(
    IsolateCameraImage data,
    int inputSize,
  ) {
    try {
      img.Image? image;

      if (data.formatGroup == 'yuv420') {
        image = _decodeYUV420(data);
      } else if (data.formatGroup == 'bgra8888') {
        image = img.Image.fromBytes(
          width: data.width,
          height: data.height,
          bytes: data.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
      } else {
        debugPrint(
          'AIModelService: unsupported camera format "${data.formatGroup}"',
        );
        return null;
      }
      // Correct sensor rotation before resizing.
      if (data.sensorOrientation != 0) {
        image = img.copyRotate(image, angle: data.sensorOrientation);
      }

      return _resizeAndLetterbox(image, inputSize);
    } catch (e) {
      return null;
    }
  }

  /// FIX (C-05): Decode YUV420 camera planes to RGB.
  /// Uses the actual [IsolatePlane.bytesPerPixel] (defaulted to 2 for Android
  /// NV12/NV21) instead of a hard-coded 1, preventing UV colour distortion.
  static img.Image _decodeYUV420(IsolateCameraImage data) {
    final output = img.Image(width: data.width, height: data.height);

    final yPlane = data.planes[0];
    final uPlane = data.planes[1];
    final vPlane = data.planes[2];

    final uPixelStride = uPlane.bytesPerPixel; // 2 for NV12/NV21 (interleaved)
    final vPixelStride = vPlane.bytesPerPixel;

    for (int h = 0; h < data.height; h++) {
      for (int w = 0; w < data.width; w++) {
        final yIndex = h * yPlane.bytesPerRow + w;
        final uIndex = (h ~/ 2) * uPlane.bytesPerRow + (w ~/ 2) * uPixelStride;
        final vIndex = (h ~/ 2) * vPlane.bytesPerRow + (w ~/ 2) * vPixelStride;

        // Bounds guard — some devices have non-standard row padding.
        if (yIndex >= yPlane.bytes.length) continue;
        if (uIndex >= uPlane.bytes.length) continue;
        if (vIndex >= vPlane.bytes.length) continue;

        final yVal = yPlane.bytes[yIndex].toDouble();
        final uVal = uPlane.bytes[uIndex].toDouble() - 128.0;
        final vVal = vPlane.bytes[vIndex].toDouble() - 128.0;

        final r = (yVal + 1.402 * vVal).round().clamp(0, 255);
        final g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(
          0,
          255,
        );
        final b = (yVal + 1.772 * uVal).round().clamp(0, 255);

        output.setPixelRgb(w, h, r, g, b);
      }
    }
    return output;
  }

  /// Aspect-ratio-preserving resize + centre letterbox to inputSize x inputSize.
  ///
  /// FIX (C-06): Returns a compact [Float32List] in CHW (channels-first) format
  /// normalised to `[0, 1]`.  This is approximately 5 MB vs 31 MB for the
  /// previous nested list approach and transfers efficiently across isolates.
  static Float32List _resizeAndLetterbox(img.Image image, int inputSize) {
    // Scale the longer side to inputSize, preserving aspect ratio.
    final scaleX = inputSize / image.width;
    final scaleY = inputSize / image.height;
    final scale = min(scaleX, scaleY);

    final targetW = (image.width * scale).round();
    final targetH = (image.height * scale).round();

    final resized = img.copyResize(
      image,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.linear,
    );

    // Centre-padding offsets.
    final dx = (inputSize - targetW) ~/ 2;
    final dy = (inputSize - targetH) ~/ 2;

    // Allocate the flat CHW buffer and pre-fill with letterbox grey.
    final buffer = Float32List(3 * inputSize * inputSize)
      ..fillRange(0, 3 * inputSize * inputSize, _letterboxFill);

    // Copy resized pixels into CHW layout.
    for (int y = 0; y < targetH; y++) {
      for (int x = 0; x < targetW; x++) {
        final pixel = resized.getPixel(x, y);
        final outY = y + dy;
        final outX = x + dx;
        final base = outY * inputSize + outX;
        buffer[0 * inputSize * inputSize + base] = pixel.r / 255.0; // R
        buffer[1 * inputSize * inputSize + base] = pixel.g / 255.0; // G
        buffer[2 * inputSize * inputSize + base] = pixel.b / 255.0; // B
      }
    }

    return buffer;
  }
}
