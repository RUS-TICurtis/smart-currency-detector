import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final cameraControllerProvider = FutureProvider.autoDispose<CameraController>((ref) async {
  // Get list of available cameras
  final cameras = await availableCameras();
  
  if (cameras.isEmpty) {
    throw Exception('No cameras available on this device.');
  }

  // Find the first back camera, or just use the first available one
  final backCamera = cameras.firstWhere(
    (camera) => camera.lensDirection == CameraLensDirection.back,
    orElse: () => cameras.first,
  );

  // Initialize the camera controller
  // We use high resolution to ensure sufficient clarity for AI detection
  // Setting enableAudio to false to avoid microphone permissions
  final controller = CameraController(
    backCamera,
    ResolutionPreset.high,
    enableAudio: false,
  );

  await controller.initialize();

  // Dispose of the controller when the provider is destroyed
  ref.onDispose(() {
    controller.dispose();
  });

  return controller;
});
