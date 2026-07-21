import 'dart:io';
import 'dart:typed_data';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() async {
  final options = InterpreterOptions()..threads = 1;
  final interpreter = await Interpreter.fromFile(
    File('assets/model/best_int8.tflite'),
    options: options,
  );
  
  final input = List.generate(1, (i) => List.generate(3, (j) => List.generate(640, (k) => List.generate(640, (l) => 0.0))));
  final output = List.generate(1, (i) => List.generate(17, (j) => List.generate(8400, (k) => 0.0)));
  
  print('Running inference with .run()');
  interpreter.run(input, output);
  print('Success!');
}
