import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final cameraControllerProvider =
    FutureProvider.autoDispose<CameraController>((ref) async {
  // FIX (H-03): Request camera permission explicitly before touching the camera
  // API.  If denied, throw a human-readable exception so the UI can surface a
  // TTS-accessible error message and an "Open Settings" button.
  final status = await Permission.camera.request();
  if (status.isPermanentlyDenied) {
    throw Exception(
      'Camera permission permanently denied. '
      'Please grant camera access in device Settings.',
    );
  }
  if (!status.isGranted) {
    throw Exception(
      'Camera permission denied. '
      'Please allow camera access to use this app.',
    );
  }

  final cameras = await availableCameras();
  if (cameras.isEmpty) {
    throw Exception('No cameras available on this device.');
  }

  // Prefer the rear camera; fall back to whatever is available.
  final backCamera = cameras.firstWhere(
    (c) => c.lensDirection == CameraLensDirection.back,
    orElse: () => cameras.first,
  );

  final controller = CameraController(
    backCamera,
    // FIX (M-04): medium (480–720 p) is sufficient for a 640×640 model input
    // and halves the preprocessing cost vs. ResolutionPreset.high.
    ResolutionPreset.medium,
    enableAudio: false,
    // FIX (H-07): Explicitly declare the format so the preprocessing branch
    // selection in AIModelService never falls through to the null-return path.
    imageFormatGroup: ImageFormatGroup.yuv420,
  );

  await controller.initialize();

  // Dispose the native controller when the provider is no longer observed.
  ref.onDispose(controller.dispose);

  return controller;
});
