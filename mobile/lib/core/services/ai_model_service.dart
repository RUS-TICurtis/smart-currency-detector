import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:typed_data';
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

class RecognizedObject {
  final int classIndex;
  final String label;
  final double confidence;
  // Bounding-box corners in pixel space (0..inputSize).
  final double x1, y1, x2, y2;

  const RecognizedObject(
    this.classIndex,
    this.label,
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
  /// Lowered from 0.45 to 0.20 to aggressively suppress duplicate boxes on the same physical note.
  static const double _nmsIouThreshold = 0.20;

  bool _isReady = false;

  // Throttle diagnostic prints to 1 per 60 frames to avoid logcat spam.
  int _frameCount = 0;

  // ── Tensor type / quantization metadata (populated in initModel) ──
  TensorType _inputType = TensorType.float32;
  TensorType _outputType = TensorType.float32;
  double _inputScale = 1.0;
  int _inputZeroPoint = 0;
  double _outputScale = 1.0;
  int _outputZeroPoint = 0;

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  /// Load the TFLite model and labels from app assets.
  /// Must be awaited before calling [predict] or [predictFromCameraImage].
  Future<void> initModel() async {
    final options = InterpreterOptions();

    // ── BUG-04 FIX: Add hardware delegates BEFORE creating the interpreter. ──
    // OEM devices. CPU INT8 is the safe, consistent default for Android.
    try {
      if (Platform.isAndroid) {
        // Use CPU thread=1 to prevent "Input tensor lacks data" crashes in YOLO exports
        options.threads = 1;
        debugPrint('AIModelService: Android — running CPU INT8 for reliability.');
      } else if (Platform.isIOS) {
        options.addDelegate(GpuDelegateV2());
        debugPrint('AIModelService: Metal/GPU delegate added (iOS).');
      }
    } catch (e) {
      debugPrint('AIModelService: delegate setup failed, using CPU. ($e)');
    }

    _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

    // ── Capture tensor types and quantization params ──
    final inTensor = _interpreter!.getInputTensor(0);
    final outTensor = _interpreter!.getOutputTensor(0);
    debugPrint('AIModelService Input: shape=${inTensor.shape}, type=${inTensor.type}, total_inputs=${_interpreter!.getInputTensors().length}');

    _inputType = inTensor.type;
    _outputType = outTensor.type;
    _inputScale = inTensor.params.scale;
    _inputZeroPoint = inTensor.params.zeroPoint;
    _outputScale = outTensor.params.scale;
    _outputZeroPoint = outTensor.params.zeroPoint;

    debugPrint(
      'AIModelService: input  type=$_inputType  scale=$_inputScale  zp=$_inputZeroPoint',
    );
    debugPrint(
      'AIModelService: output type=$_outputType scale=$_outputScale zp=$_outputZeroPoint',
    );

    final rawLabels = await rootBundle.loadString(_labelPath);
    _labels = rawLabels
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // ── Sanity check: label count must match model output classes ──
    final outputShape = outTensor.shape;
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
  Future<List<RecognizedObject>?> predict(
    String imagePath,
    double confidenceThreshold,
  ) async {
    if (!_isReady) return null;
    try {
      // Preprocessing is CPU-heavy — offload to a background isolate.
      // Float32List is a TypedData and transfers efficiently across isolates.
      final isolateInput = await Isolate.run(
        () => _preprocessImageToFloat32(imagePath, inputSize),
      );
      if (isolateInput == null) return null;
      
      // Deep copy to break Isolate TransferableTypedData memory linkage
      final input = Float32List.fromList(isolateInput);
      // Create a clean, temporary Interpreter to avoid any corrupted state or 
      // concurrent memory issues with the Auto-scan interpreter.
      final options = InterpreterOptions();
      if (Platform.isAndroid) {
        options.threads = 1;
        options.useNnApiForAndroid = true;
      } else if (Platform.isIOS) {
        options.addDelegate(GpuDelegate());
      }
      final tempInterpreter = await Interpreter.fromAsset(
        _modelPath,
        options: options,
      );

      final results = _runInference(tempInterpreter, input, confidenceThreshold);
      tempInterpreter.close();
      return results;
    } catch (e) {
      debugPrint('AIModelService: gallery inference error: $e');
      return null;
    }
  }

  /// Run inference on a live [CameraImage] frame from the camera stream.
  Future<List<RecognizedObject>?> predictFromCameraImage(
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
      return _runInference(_interpreter!, input, confidenceThreshold);
    } catch (e) {
      debugPrint('AIModelService: camera inference error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Inference core (runs on main isolate — interpreter lives here)
  // ---------------------------------------------------------------------------

  /// Returns a list of all detected objects after NMS.
  ///
  /// Uses raw byte buffers (setTo / invoke / tensor.data) instead of
  /// tflite_flutter's [run] helper.  The nested-list path in tflite_flutter
  /// 0.10.4 writes each leaf row to offset 0 of the tensor buffer, leaving
  /// only the last row in memory — producing the native error
  /// "Input tensor N lacks data / failed precondition".
  List<RecognizedObject>? _runInference(
    Interpreter interpreter,
    Float32List flatInput,
    double confidenceThreshold,
  ) {
    _frameCount++;
    final bool logThisFrame = (_frameCount % 60) == 0;

    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);

    final outputShape = outputTensor.shape;
    // YOLOv11 raw output can be NCHW [1, 4+numClasses, numAnchors]
    // or TFLite NHWC permuted [1, numAnchors, 4+numClasses].
    final bool isNhwc = outputShape[1] > outputShape[2];
    final int numAnchors = isNhwc ? outputShape[1] : outputShape[2];
    final int numFeatures = isNhwc ? outputShape[2] : outputShape[1];
    final int numClasses = numFeatures - 4;

    // ── Set input via raw bytes ─────────────────────────────────────────────
    // setTo(Uint8List) writes the entire buffer atomically — safe for any size.
    if (_inputType == TensorType.int8 || _inputType == TensorType.uint8) {
      // Full integer quantization: float → int8 / uint8
      final isUint8 = _inputType == TensorType.uint8;
      final qMin = isUint8 ? 0 : -128;
      final qMax = isUint8 ? 255 : 127;
      if (isUint8) {
        final quantized = Uint8List(flatInput.length);
        for (int i = 0; i < flatInput.length; i++) {
          quantized[i] =
              ((flatInput[i] / _inputScale).round() + _inputZeroPoint).clamp(
                qMin,
                qMax,
              );
        }
        inputTensor.setTo(quantized);
      } else {
        final quantized = Int8List(flatInput.length);
        for (int i = 0; i < flatInput.length; i++) {
          quantized[i] =
              ((flatInput[i] / _inputScale).round() + _inputZeroPoint).clamp(
                qMin,
                qMax,
              );
        }
        inputTensor.setTo(Uint8List.sublistView(quantized));
      }
    } else {
      // float32 / dynamic-range-quant — copy raw bytes directly
      // Use sublistView to safely handle Isolate-transferred TypedData offsets
      inputTensor.setTo(Uint8List.sublistView(flatInput));
    }

    // ── Invoke ──────────────────────────────────────────────────────────────
    interpreter.invoke();

    // ── Read output via raw bytes ────────────────────────────────────────────
    final outRawBytes = outputTensor.data; // Uint8List
    final outInt8Bytes = outRawBytes.buffer.asInt8List(
      outRawBytes.offsetInBytes,
      outRawBytes.lengthInBytes,
    );

    // ── 1. Parse raw anchors into candidate detections ──────────────────────
    final detections = <RecognizedObject>[];
    double topRawScore = 0.0;

    if (_outputType == TensorType.int8 || _outputType == TensorType.uint8) {
      // Full integer output: read raw bytes and dequantize per element.
      final isUint8 = _outputType == TensorType.uint8;
      for (int a = 0; a < numAnchors; a++) {
        double maxScore = 0.0;
        int bestClass = -1;
        for (int c = 0; c < numClasses; c++) {
          final idx = isNhwc
              ? (a * numFeatures + (4 + c))
              : ((4 + c) * numAnchors + a);
          final raw = isUint8 ? outRawBytes[idx] : outInt8Bytes[idx];
          final score = (raw - _outputZeroPoint) * _outputScale;
          if (score > maxScore) {
            maxScore = score;
            bestClass = c;
          }
        }

        if (maxScore > topRawScore) topRawScore = maxScore;
        if (maxScore < confidenceThreshold) continue;
        if (bestClass < 0 || bestClass >= (_labels?.length ?? 0)) continue;

        double deq(int featureIdx) {
          final idx = isNhwc
              ? (a * numFeatures + featureIdx)
              : (featureIdx * numAnchors + a);
          final raw = isUint8 ? outRawBytes[idx] : outInt8Bytes[idx];
          return (raw - _outputZeroPoint) * _outputScale;
        }

        final cx = deq(0);
        final cy = deq(1);
        final bw = deq(2);
        final bh = deq(3);
        detections.add(
          RecognizedObject(
            bestClass,
            _labels![bestClass],
            maxScore,
            cx - bw / 2,
            cy - bh / 2,
            cx + bw / 2,
            cy + bh / 2,
          ),
        );
      }
    } else {
      // float32 output — view the byte buffer as a flat Float32List
      final outF32 = outRawBytes.buffer.asFloat32List(
        outRawBytes.offsetInBytes,
        outRawBytes.lengthInBytes ~/ 4,
      );

      for (int a = 0; a < numAnchors; a++) {
        double maxScore = 0.0;
        int bestClass = -1;
        for (int c = 0; c < numClasses; c++) {
          final idx = isNhwc
              ? (a * numFeatures + (4 + c))
              : ((4 + c) * numAnchors + a);
          final score = outF32[idx];
          if (score > maxScore) {
            maxScore = score;
            bestClass = c;
          }
        }

        if (maxScore > topRawScore) topRawScore = maxScore;
        if (maxScore < confidenceThreshold) continue;
        if (bestClass < 0 || bestClass >= (_labels?.length ?? 0)) continue;

        double f32(int featureIdx) {
          return outF32[isNhwc
              ? (a * numFeatures + featureIdx)
              : (featureIdx * numAnchors + a)];
        }

        final cx = f32(0);
        final cy = f32(1);
        final bw = f32(2);
        final bh = f32(3);
        detections.add(
          RecognizedObject(
            bestClass,
            _labels![bestClass],
            maxScore,
            cx - bw / 2,
            cy - bh / 2,
            cx + bw / 2,
            cy + bh / 2,
          ),
        );
      }
    }

    if (logThisFrame) {
      debugPrint(
        'AIModelService [frame $_frameCount]: '
        'topScore=${topRawScore.toStringAsFixed(4)} '
        'threshold=$confidenceThreshold '
        'candidates=${detections.length} '
        'outType=$_outputType scale=$_outputScale zp=$_outputZeroPoint',
      );
    }

    debugPrint('AIModelService: Top score = $topRawScore, found ${detections.length} pre-NMS');
    if (detections.isEmpty) return null;

    // ── 2. Apply Non-Maximum Suppression ──
    final kept = applyNMS(detections, _nmsIouThreshold);
    if (kept.isEmpty) return null;

    // ── 3. Return all surviving detections ──
    kept.sort((a, b) => b.confidence.compareTo(a.confidence));
    return kept;
  }

  // ---------------------------------------------------------------------------
  // Non-Maximum Suppression
  // ---------------------------------------------------------------------------

  @visibleForTesting
  static List<RecognizedObject> applyNMS(
    List<RecognizedObject> detections,
    double iouThreshold,
  ) {
    // Sort descending by confidence so higher-quality boxes win.
    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Cap at top 100 to prevent O(N^2) explosion
    if (detections.length > 100) {
      detections = detections.sublist(0, 100);
    }

    final suppressed = List<bool>.filled(detections.length, false);
    final kept = <RecognizedObject>[];

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;
      kept.add(detections[i]);
      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;
        if (iou(detections[i], detections[j]) > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return kept;
  }

  @visibleForTesting
  static double iou(RecognizedObject a, RecognizedObject b) {
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
      if (data.formatGroup != 'bgra8888' && data.formatGroup != 'yuv420') {
        debugPrint(
          'AIModelService: unsupported camera format "${data.formatGroup}". Expected bgra8888 or yuv420.',
        );
        return null;
      }

      return _fastResizeAndLetterbox(data, inputSize);
    } catch (e) {
      debugPrint('AIModelService: preprocessing error: $e');
      return null;
    }
  }

  /// High-performance nearest-neighbor resize + letterbox directly from raw bytes.
  /// Bypasses the `image` package to avoid allocations and massive CPU overhead.
  /// Reads only the exact pixels needed for the 640x640 output.
  static Float32List _fastResizeAndLetterbox(
    IsolateCameraImage data,
    int inputSize,
  ) {
    final srcWidth = data.width;
    final srcHeight = data.height;
    final orientation = data.sensorOrientation;

    // Determine effective dimensions after rotation
    final bool isPortrait = orientation == 90 || orientation == 270;
    final effWidth = isPortrait ? srcHeight : srcWidth;
    final effHeight = isPortrait ? srcWidth : srcHeight;

    // Scale and letterbox dimensions
    final scale = min(inputSize / effWidth, inputSize / effHeight);
    final targetW = (effWidth * scale).round();
    final targetH = (effHeight * scale).round();
    final dx = (inputSize - targetW) ~/ 2;
    final dy = (inputSize - targetH) ~/ 2;

    // Allocate the flat HWC buffer (NHWC layout: [R,G,B interleaved per pixel])
    final buffer = Float32List(3 * inputSize * inputSize)
      ..fillRange(0, 3 * inputSize * inputSize, _letterboxFill);

    final isYUV = data.formatGroup == 'yuv420';
    final p0 = data.planes[0];
    final p1 = data.planes.length > 1 ? data.planes[1] : p0;
    // BUG-06 FIX: Fall back to p1 (chroma) rather than p0 (luma) when fewer
    // than 3 planes are reported. In NV21/NV12 semi-planar format planes[1] and
    // planes[2] reference the same interleaved UV buffer with a 1-byte offset,
    // so p1 is always a better chroma substitute than the Y plane (p0).
    final p2 = data.planes.length > 2 ? data.planes[2] : p1;

    for (int y = 0; y < targetH; y++) {
      final effY = (y / scale).floor().clamp(0, effHeight - 1);

      for (int x = 0; x < targetW; x++) {
        final effX = (x / scale).floor().clamp(0, effWidth - 1);

        // Map effective (rotated) coords back to raw source coords
        int srcX, srcY;
        switch (orientation) {
          case 90:
            srcX = effY;
            srcY = srcHeight - 1 - effX;
            break;
          case 180:
            srcX = srcWidth - 1 - effX;
            srcY = srcHeight - 1 - effY;
            break;
          case 270:
            srcX = srcWidth - 1 - effY;
            srcY = effX;
            break;
          default: // 0
            srcX = effX;
            srcY = effY;
        }

        double r = 0, g = 0, b = 0;

        if (isYUV) {
          // YUV420 to RGB
          final yIndex = srcY * p0.bytesPerRow + srcX;
          final uvX = srcX ~/ 2;
          final uvY = srcY ~/ 2;

          final uIndex = uvY * p1.bytesPerRow + uvX * p1.bytesPerPixel;
          final yVal = p0.bytes[yIndex];
          final uVal = p1.bytes[uIndex];

          int vVal;
          if (data.planes.length > 2) {
            final vIndex = uvY * p2.bytesPerRow + uvX * p2.bytesPerPixel;
            vVal = p2.bytes[vIndex];
          } else {
            // If only 2 planes exist, UV are interleaved in p1. The next byte is V.
            vVal = (uIndex + 1 < p1.bytes.length) ? p1.bytes[uIndex + 1] : uVal;
          }

          final c = yVal - 16;
          final d = uVal - 128;
          final e = vVal - 128;

          r = (1.164 * c + 1.596 * e).clamp(0, 255) / 255.0;
          g = (1.164 * c - 0.391 * d - 0.813 * e).clamp(0, 255) / 255.0;
          b = (1.164 * c + 2.018 * d).clamp(0, 255) / 255.0;
        } else {
          // BGRA8888 to RGB
          final offset = srcY * p0.bytesPerRow + srcX * 4;
          b = p0.bytes[offset] / 255.0;
          g = p0.bytes[offset + 1] / 255.0;
          r = p0.bytes[offset + 2] / 255.0;
        }

        final outY = y + dy;
        final outX = x + dx;
        // CHW planar layout matching PyTorch native export [1,3,640,640]
        final base = outY * inputSize + outX;
        buffer[0 * inputSize * inputSize + base] = r; // R
        buffer[1 * inputSize * inputSize + base] = g; // G
        buffer[2 * inputSize * inputSize + base] = b; // B
      }
    }

    return buffer;
  }

  /// Aspect-ratio-preserving resize + centre letterbox to inputSize x inputSize.
  /// Used for still images (gallery/takePicture) loaded via `img` package.
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

    // Allocate the flat HWC buffer (NHWC layout: [R,G,B interleaved per pixel])
    final buffer = Float32List(3 * inputSize * inputSize)
      ..fillRange(0, 3 * inputSize * inputSize, _letterboxFill);

    // Copy resized pixels into CHW layout.
    for (int y = 0; y < targetH; y++) {
      for (int x = 0; x < targetW; x++) {
        final pixel = resized.getPixel(x, y);
        final outY = y + dy;
        final outX = x + dx;
        // CHW planar layout matching PyTorch native export [1,3,640,640]
        final base = outY * inputSize + outX;
        buffer[0 * inputSize * inputSize + base] = pixel.r / 255.0; // R
        buffer[1 * inputSize * inputSize + base] = pixel.g / 255.0; // G
        buffer[2 * inputSize * inputSize + base] = pixel.b / 255.0; // B
      }
    }

    return buffer;
  }
}
