import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:image_picker/image_picker.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'providers/camera_provider.dart';
import 'providers/ai_provider.dart';
import '../speech/providers/speech_provider.dart';
import '../settings/providers/settings_provider.dart';

class CameraScreen extends HookConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cameraState = ref.watch(cameraControllerProvider);
    final settings = ref.watch(settingsProvider);
    final scanStatus = useState('Ready to scan');
    final isProcessing = useState(false);
    final isFlashOn = useState(false);
    
    final latestImage = useRef<CameraImage?>(null);
    final lastAutoScanTime = useRef<DateTime>(DateTime.now());
    final detectionHistory = useRef<List<String>>([]);

    // Auto-Scan & Live Stream Logic
    useEffect(() {
      if (cameraState.hasValue && !cameraState.isLoading && !cameraState.hasError) {
        final controller = cameraState.value!;
        
        // Apply camera zoom setting safely
        controller.setZoomLevel(settings.cameraZoom).catchError((e) {
          debugPrint('Failed to set zoom: $e');
        });

        // 1. Battery Optimization: Only start stream if autoScan is enabled
        if (settings.autoScan) {
          if (!controller.value.isStreamingImages) {
            controller.startImageStream((image) {
              latestImage.value = image;
              
              if (!isProcessing.value) {
                final now = DateTime.now();
                if (now.difference(lastAutoScanTime.value) > const Duration(seconds: 2)) {
                  lastAutoScanTime.value = now;
                  
                  isProcessing.value = true;
                  scanStatus.value = 'Auto-scanning...';
                  
                  final aiService = ref.read(aiServiceProvider);
                  aiService.predictFromCameraImage(image, controller.description.sensorOrientation, settings.confidenceThreshold).then((prediction) {
                    if (prediction != null) {
                      // Multi-Frame Consensus logic
                      detectionHistory.value.add(prediction);
                      if (detectionHistory.value.length >= 3) {
                        // Check if the last 3 detections are the same
                        bool allSame = detectionHistory.value.every((p) => p == prediction);
                        if (allSame) {
                          scanStatus.value = 'Detected: $prediction';
                          ref.read(speechServiceProvider).speak('Detected $prediction');
                          detectionHistory.value.clear(); // Reset history after speaking
                        } else {
                          // Keep only the last 3 elements
                          detectionHistory.value.removeAt(0);
                        }
                      } else {
                        scanStatus.value = 'Verifying...';
                      }
                    } else {
                      detectionHistory.value.clear(); // Reset if we lose confidence
                      scanStatus.value = 'Scanning...';
                    }
                    isProcessing.value = false;
                  }).catchError((e) {
                    isProcessing.value = false;
                  });
                }
              }
            });
          }
        } else {
          // Auto-Scan is OFF -> Stop streaming to save battery
          if (controller.value.isStreamingImages) {
            controller.stopImageStream();
            latestImage.value = null; // Clear stale frames
          }
        }
      }
      
      return () {
        if (cameraState.hasValue && cameraState.value!.value.isStreamingImages) {
          cameraState.value!.stopImageStream();
        }
      };
    }, [cameraState.hasValue, settings.autoScan, settings.cameraZoom, settings.confidenceThreshold]);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Full-Screen Camera Background (Uncropped AR style)
          Positioned.fill(
            child: cameraState.when(
              data: (controller) {
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: CameraPreview(controller),
                  ),
                );
              },
              error: (error, stackTrace) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 60, color: theme.colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load camera:\n$error',
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),

          // 2. Floating Action Buttons (Top Right)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 16,
            right: 16,
            child: Column(
              children: [
                // Settings Button
                Container(
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white),
                    tooltip: 'Settings',
                    iconSize: 28,
                    onPressed: () {
                      context.push('/settings');
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Flashlight Button
                if (cameraState.hasValue && !cameraState.isLoading && !cameraState.hasError)
                  Container(
                    decoration: BoxDecoration(
                      color: isFlashOn.value ? theme.colorScheme.primary : Colors.black.withOpacity(0.4), 
                      shape: BoxShape.circle
                    ),
                    child: IconButton(
                      icon: Icon(
                        isFlashOn.value ? Icons.flash_on : Icons.flash_off, 
                        color: isFlashOn.value ? theme.colorScheme.onPrimary : Colors.white
                      ),
                      tooltip: 'Toggle Flashlight',
                      iconSize: 28,
                      onPressed: () async {
                        final controller = cameraState.value!;
                        try {
                          final newMode = isFlashOn.value ? FlashMode.off : FlashMode.torch;
                          await controller.setFlashMode(newMode);
                          isFlashOn.value = !isFlashOn.value;
                        } catch (e) {
                          debugPrint('Failed to toggle flash: $e');
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),

          // 3. Floating Interaction Area (Bottom)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: MediaQuery.paddingOf(context).bottom + 24,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.75),
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2), width: 1),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status Text
                      Text(
                        scanStatus.value,
                        style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        semanticsLabel: 'Status: ${scanStatus.value}',
                      ),
                      const SizedBox(height: 24),
                      
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 72,
                              child: ElevatedButton.icon(
                                onPressed: cameraState.isLoading || cameraState.hasError || isProcessing.value
                                  ? null 
                                  : () async {
                                      isProcessing.value = true;
                                      scanStatus.value = 'Scanning note...';
                                      final speechService = ref.read(speechServiceProvider);
                                      await speechService.speak('Scanning note. Please hold steady.');
                                      
                                      try {
                                        final controller = cameraState.value!;
                                        final aiService = ref.read(aiServiceProvider);
                                        String? prediction;
                                        
                                        scanStatus.value = 'Analyzing...';
                                        
                                        // If streaming, use stream frame. Else take picture.
                                        if (settings.autoScan) {
                                          final image = latestImage.value;
                                          if (image == null) throw Exception('No camera frame ready');
                                          prediction = await aiService.predictFromCameraImage(image, controller.description.sensorOrientation, settings.confidenceThreshold);
                                        } else {
                                          final xFile = await controller.takePicture();
                                          prediction = await aiService.predict(xFile.path, settings.confidenceThreshold);
                                        }
                                        
                                        if (prediction != null) {
                                          scanStatus.value = 'Detected: $prediction';
                                          await speechService.speak('Detected $prediction');
                                        } else {
                                          scanStatus.value = 'Could not detect note.';
                                          await speechService.speak('Could not clearly detect the note.');
                                        }
                                      } catch (e) {
                                        scanStatus.value = 'Scan failed.';
                                        await speechService.speak('An error occurred during scan.');
                                      } finally {
                                        isProcessing.value = false;
                                      }
                                  },
                                icon: const Icon(Icons.document_scanner, size: 28),
                                label: const Text('SCAN NOTE'),
                                style: ElevatedButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SizedBox(
                              height: 72,
                              child: ElevatedButton.icon(
                                onPressed: isProcessing.value ? null : () async {
                                  final picker = ImagePicker();
                                  try {
                                    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                                    if (pickedFile != null) {
                                      isProcessing.value = true;
                                      scanStatus.value = 'Analyzing image...';
                                      
                                      final aiService = ref.read(aiServiceProvider);
                                      final speechService = ref.read(speechServiceProvider);
                                      final prediction = await aiService.predict(pickedFile.path, settings.confidenceThreshold);
                                      
                                      if (prediction != null) {
                                        scanStatus.value = 'Detected: $prediction';
                                        await speechService.speak('Detected $prediction');
                                      } else {
                                        scanStatus.value = 'Could not detect note.';
                                        await speechService.speak('Could not clearly detect the note.');
                                      }
                                      isProcessing.value = false;
                                    }
                                  } catch (e) {
                                    scanStatus.value = 'Upload failed.';
                                    isProcessing.value = false;
                                  }
                                },
                                icon: const Icon(Icons.photo_library, size: 28),
                                label: const Text('GALLERY'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.secondaryContainer,
                                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
