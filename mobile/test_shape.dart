import 'dart:io';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() {
  final interpreter = Interpreter.fromFile(File('assets/model/best_int8.tflite'));
  final inputTensor = interpreter.getInputTensor(0);
  final outputTensor = interpreter.getOutputTensor(0);

  print('Input shape: ${inputTensor.shape}');
  print('Input type: ${inputTensor.type}');
  print('Output shape: ${outputTensor.shape}');
  print('Output type: ${outputTensor.type}');
}
