import 'dart:io';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class AIModelService {
  Interpreter? _interpreter;
  List<String>? _labels;
  
  static const String modelPath = 'assets/model/currency_detector.tflite';
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
      
      print('Model and labels loaded successfully');
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

  Future<String?> predict(String imagePath) async {
    if (_interpreter == null || _labels == null) {
      print('Interpreter not initialized');
      return null;
    }

    try {
      // 1. Read and decode the image file
      final bytes = await File(imagePath).readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // 2. Resize image to model input size
      img.Image resizedImage = img.copyResize(image, width: inputSize, height: inputSize);

      // 3. Convert image to a 3D float array [1, inputSize, inputSize, 3]
      // YOLOv11 expects inputs scaled between 0.0 and 1.0 (mean=0, std=255)
      var input = _imageToByteListFloat32(resizedImage, inputSize, 0, 255.0);

      // 4. Get output tensor shape to dynamically allocate buffer
      // YOLOv11 output shape is typically [1, num_classes + 4, num_anchors] (e.g. [1, 11, 8400])
      var outputShape = _interpreter!.getOutputTensor(0).shape;
      int numRows = outputShape[1]; // e.g., 11
      int numAnchors = outputShape[2]; // e.g., 8400

      // Prepare output buffer
      var output = List.generate(1, (i) => List.generate(numRows, (j) => List.filled(numAnchors, 0.0)));

      // 5. Run inference
      _interpreter!.run(input, output);

      // 6. Parse YOLO Output to find the highest confidence class
      double maxConfidence = 0.0;
      int bestClassIndex = -1;

      // Iterate through all anchors to find the best detection
      for (int anchor = 0; anchor < numAnchors; anchor++) {
        // Classes start at row 4 (after x, y, width, height)
        for (int cls = 0; cls < _labels!.length; cls++) {
          double confidence = output[0][cls + 4][anchor];
          if (confidence > maxConfidence) {
            maxConfidence = confidence;
            bestClassIndex = cls;
          }
        }
      }

      print('Best detection: ${_labels![bestClassIndex]} with confidence $maxConfidence');

      // If confidence is low, return a fallback message
      if (maxConfidence < 0.5) {
        return "Could not clearly detect the note. Please try again.";
      }

      return _labels![bestClassIndex];
    } catch (e) {
      print('Error running inference: $e');
      return null;
    }
  }

  // Converts an img.Image to a float32 tensor
  List<List<List<List<double>>>> _imageToByteListFloat32(
      img.Image image, int inputSize, double mean, double std) {
    var convertedBytes = List.generate(
      1,
      (i) => List.generate(
        inputSize,
        (y) => List.generate(
          inputSize,
          (x) {
            final pixel = image.getPixel(x, y);
            return [
              (pixel.r - mean) / std,
              (pixel.g - mean) / std,
              (pixel.b - mean) / std,
            ];
          },
        ),
      ),
    );
    return convertedBytes;
  }
}
