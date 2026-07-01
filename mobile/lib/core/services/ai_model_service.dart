import 'dart:io';
import 'dart:isolate';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class IsolateCameraImage {
  final int width;
  final int height;
  final String formatGroup;
  final List<IsolatePlane> planes;
  final int sensorOrientation;
  IsolateCameraImage(this.width, this.height, this.formatGroup, this.planes, this.sensorOrientation);
}

class IsolatePlane {
  final Uint8List bytes;
  final int bytesPerRow;
  final int? bytesPerPixel;
  IsolatePlane(this.bytes, this.bytesPerRow, this.bytesPerPixel);
}

class AIModelService {
  Interpreter? _interpreter;
  List<String>? _labels;
  
  static const String modelPath = 'assets/model/best.tflite';
  static const String labelPath = 'assets/model/labels.txt';
  
  // Update this to match your Roboflow model's input size
  static const int inputSize = 640;

  Future<void> initModel() async {
    try {
      final options = InterpreterOptions();
      
      // Load the model
      _interpreter = await Interpreter.fromAsset(modelPath, options: options);
      
      // Load labels
      final labelData = await rootBundle.loadString(labelPath);
      _labels = labelData.split('\n').where((label) => label.isNotEmpty).toList();
      
      debugPrint('Model and labels loaded successfully');
    } catch (e) {
      debugPrint('Failed to load model: $e');
    }
  }

  Future<String?> predict(String imagePath, double confidenceThreshold) async {
    if (_interpreter == null || _labels == null) return null;
    try {
      final input = await Isolate.run(() => _preprocessImage(imagePath, inputSize));
      if (input == null) return null;
      return _runInference(input, confidenceThreshold);
    } catch (e) {
      debugPrint('Error running inference: $e');
      return null;
    }
  }

  Future<String?> predictFromCameraImage(CameraImage image, int sensorOrientation, double confidenceThreshold) async {
    if (_interpreter == null || _labels == null) return null;
    try {
      // Extract bytes on main thread to avoid Isolate serialization errors
      final planes = image.planes.map((p) => IsolatePlane(
        p.bytes, p.bytesPerRow, p.bytesPerPixel
      )).toList();
      
      final isolateData = IsolateCameraImage(
        image.width, image.height, image.format.group.name, planes, sensorOrientation
      );

      final input = await Isolate.run(() => _preprocessCameraImage(isolateData, inputSize));
      if (input == null) return null;
      return _runInference(input, confidenceThreshold);
    } catch (e) {
      debugPrint('Error running camera inference: $e');
      return null;
    }
  }

  String? _runInference(List<List<List<List<double>>>> input, double confidenceThreshold) {
    var outputShape = _interpreter!.getOutputTensor(0).shape;
    int numRows = outputShape[1]; 
    int numAnchors = outputShape[2]; 

    var output = List.generate(1, (i) => List.generate(numRows, (j) => List.filled(numAnchors, 0.0)));
    _interpreter!.run(input, output);

    double maxConfidence = 0.0;
    int bestClassIndex = -1;

    for (int anchor = 0; anchor < numAnchors; anchor++) {
      for (int cls = 0; cls < _labels!.length; cls++) {
        double confidence = output[0][cls + 4][anchor];
        if (confidence > maxConfidence) {
          maxConfidence = confidence;
          bestClassIndex = cls;
        }
      }
    }

    if (maxConfidence < confidenceThreshold) {
      return null; // Return null when nothing is clearly detected
    }

    return _labels![bestClassIndex];
  }

  static List<List<List<List<double>>>>? _preprocessImage(String imagePath, int inputSize) {
    try {
      final bytes = File(imagePath).readAsBytesSync();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;
      return _resizeAndFormat(image, inputSize);
    } catch (e) {
      return null;
    }
  }

  static List<List<List<List<double>>>>? _preprocessCameraImage(IsolateCameraImage data, int inputSize) {
    try {
      img.Image? image;
      
      if (data.formatGroup == 'yuv420') {
        image = img.Image(width: data.width, height: data.height);
        final int uRowStride = data.planes[1].bytesPerRow;
        final int uPixelStride = data.planes[1].bytesPerPixel ?? 1;
        
        final int vRowStride = data.planes[2].bytesPerRow;
        final int vPixelStride = data.planes[2].bytesPerPixel ?? 1;

        for (int w = 0; w < data.width; w++) {
          for (int h = 0; h < data.height; h++) {
            final int uIndex = uPixelStride * (w ~/ 2) + uRowStride * (h ~/ 2);
            final int vIndex = vPixelStride * (w ~/ 2) + vRowStride * (h ~/ 2);
            final int index = h * data.planes[0].bytesPerRow + w;

            final y = data.planes[0].bytes[index];
            final u = data.planes[1].bytes[uIndex];
            final v = data.planes[2].bytes[vIndex];

            double yVal = y.toDouble();
            double uVal = u.toDouble() - 128.0;
            double vVal = v.toDouble() - 128.0;

            int r = (yVal + 1.402 * vVal).round().clamp(0, 255);
            int g = (yVal - 0.344136 * uVal - 0.714136 * vVal).round().clamp(0, 255);
            int b = (yVal + 1.772 * uVal).round().clamp(0, 255);
            
            image.setPixelRgb(w, h, r, g, b);
          }
        }
      } else if (data.formatGroup == 'bgra8888') {
        image = img.Image.fromBytes(
          width: data.width, 
          height: data.height, 
          bytes: data.planes[0].bytes.buffer, 
          order: img.ChannelOrder.bgra
        );
      } else {
        return null;
      }
      
      // Fix rotation before resizing
      if (data.sensorOrientation != 0) {
        image = img.copyRotate(image, angle: data.sensorOrientation);
      }

      return _resizeAndFormat(image, inputSize);
    } catch (e) {
      return null;
    }
  }

  static List<List<List<List<double>>>> _resizeAndFormat(img.Image image, int inputSize) {
    int targetWidth;
    int targetHeight;
    if (image.width > image.height) {
      targetWidth = inputSize;
      targetHeight = (image.height * inputSize / image.width).round();
    } else {
      targetHeight = inputSize;
      targetWidth = (image.width * inputSize / image.height).round();
    }
    
    img.Image resizedImage = img.copyResize(image, width: targetWidth, height: targetHeight, interpolation: img.Interpolation.linear);
    return _imageToByteListFloat32(resizedImage, inputSize, 0, 255.0);
  }

  static List<List<List<List<double>>>> _imageToByteListFloat32(
      img.Image image, int inputSize, double mean, double std) {
      
    var convertedBytes = List.generate(
      1, (_) => List.generate(3, (_) => List.generate(inputSize, (_) => List.filled(inputSize, 0.0)))
    );

    int dx = (inputSize - image.width) ~/ 2;
    int dy = (inputSize - image.height) ~/ 2;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        if (x < dx || x >= dx + image.width || y < dy || y >= dy + image.height) {
          double gray = (114.0 - mean) / std; 
          convertedBytes[0][0][y][x] = gray;
          convertedBytes[0][1][y][x] = gray;
          convertedBytes[0][2][y][x] = gray;
        } else {
          final pixel = image.getPixel(x - dx, y - dy);
          convertedBytes[0][0][y][x] = (pixel.r - mean) / std; 
          convertedBytes[0][1][y][x] = (pixel.g - mean) / std; 
          convertedBytes[0][2][y][x] = (pixel.b - mean) / std; 
        }
      }
    }
    return convertedBytes;
  }
}
