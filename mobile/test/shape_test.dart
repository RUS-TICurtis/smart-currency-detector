import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  test('Check Model Shape', () {
    final modelPath = '${Directory.current.path}/assets/model/best_int8.tflite';
    try {
      final interpreter = Interpreter.fromFile(File(modelPath));
      print('Model loaded successfully.');
      
      final inputTensors = interpreter.getInputTensors();
      print('Input tensors: ${inputTensors.length}');
      for (var i = 0; i < inputTensors.length; i++) {
        final t = inputTensors[i];
        print('Input $i: name=${t.name}, type=${t.type}, shape=${t.shape}');
      }
      
      final outputTensors = interpreter.getOutputTensors();
      print('Output tensors: ${outputTensors.length}');
      for (var i = 0; i < outputTensors.length; i++) {
        final t = outputTensors[i];
        print('Output $i: name=${t.name}, type=${t.type}, shape=${t.shape}');
      }
    } catch (e) {
      print('Error loading model: $e');
    }
  });
}
