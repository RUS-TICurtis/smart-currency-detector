import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'providers/camera_provider.dart';
import 'providers/ai_provider.dart';
import 'widgets/bounding_box_overlay.dart';
import '../../../core/services/ai_model_service.dart';
import '../speech/providers/speech_provider.dart';
import '../settings/providers/settings_provider.dart';

// ---------------------------------------------------------------------------
// Lifecycle observer — pauses the camera stream and torch when the OS
// backgrounds the app, then lets the autoScan effect resume them.
// ---------------------------------------------------------------------------

class _CameraLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onPause;
  final VoidCallback onResume;

  _CameraLifecycleObserver({required this.onPause, required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      onPause();
    } else if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

// ---------------------------------------------------------------------------
// Camera Screen
// ---------------------------------------------------------------------------

class CameraScreen extends HookConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cameraState = ref.watch(cameraControllerProvider);
    final aiState = ref.watch(aiServiceProvider); // FutureProvider<AIModelService>
    final settings = ref.watch(settingsProvider);

    // ── Local state ──
    final scanStatus = useState('Loading model...');
    final isProcessing = useState(false);
    final isFlashOn = useState(false);

    // FIX (H-04): Track mount state via a ValueNotifier so async callbacks
    // can safely check before calling setState on a disposed widget.
    // useIsMounted() is deprecated on Flutter 3.7+; we use a manual
    // WidgetsBinding post-frame guard instead.
    bool disposed = false;
    useEffect(() {
      return () { disposed = true; };
    }, const []);
    bool isMounted() => !disposed;

    // Internal refs — mutations don't need to trigger a rebuild.
    final latestImage = useRef<CameraImage?>(null);
    final lastAutoScanTime = useRef<DateTime>(DateTime.now());
    
    // Aggregation history for multi-note detection.
    final detectionHistory = useRef<List<Map<String, int>>>([]);
    final lastSpokenText = useRef<String>('');
    
    // Notifier to instantly update the bounding box overlay without full rebuilds.
    final currentDetections = useValueNotifier<List<RecognizedObject>>([]);

    // Update status when model/camera become ready
    useEffect(() {
      if (aiState.hasError) {
        scanStatus.value = 'Model failed to load.';
      } else if (aiState.isLoading) {
        scanStatus.value = 'Loading model...';
      } else if (cameraState.hasValue && !cameraState.isLoading) {
        // Only update status if not currently scanning
        if (scanStatus.value == 'Loading model...') {
          scanStatus.value = 'Ready to scan';
        }
      }
      return null;
    }, [aiState.isLoading, aiState.hasError, cameraState.hasValue]);

    // ── Effect 1: Apply zoom (FIX M-10: separated from stream effect) ──
    useEffect(() {
      if (cameraState.hasValue &&
          !cameraState.isLoading &&
          !cameraState.hasError) {
        cameraState.value!.setZoomLevel(settings.cameraZoom).catchError((e) {
          debugPrint('Failed to set zoom: $e');
        });
      }
      return null;
    }, [cameraState.hasValue, settings.cameraZoom]);

    // ── Effect 2: Lifecycle observer — pause/resume camera resources ──
    // FIX (H-06, M-07): stop stream and torch when app is backgrounded.
    useEffect(() {
      if (!cameraState.hasValue ||
          cameraState.isLoading ||
          cameraState.hasError) {
        return null;
      }

      final controller = cameraState.value!;

      final observer = _CameraLifecycleObserver(
        onPause: () {
          // Stop the image stream to release camera & save battery.
          if (controller.value.isStreamingImages) {
            controller.stopImageStream().catchError((_) {});
          }
          // Turn off torch — the OS may revoke it anyway; ensure state is synced.
          if (isFlashOn.value) {
            controller.setFlashMode(FlashMode.off).catchError((_) {});
            if (isMounted()) isFlashOn.value = false;
          }
        },
        onResume: () {
          // The autoScan effect (Effect 3) will restart the stream if needed.
          debugPrint('CameraScreen: app resumed.');
        },
      );

      WidgetsBinding.instance.addObserver(observer);
      return () => WidgetsBinding.instance.removeObserver(observer);
    }, [cameraState.hasValue, cameraState.isLoading, cameraState.hasError]);

    // ── Effect 3: Auto-scan stream (FIX C-04, H-04, M-02, M-10) ──
    useEffect(() {
      final cameraReady = cameraState.hasValue &&
          !cameraState.isLoading &&
          !cameraState.hasError;
      final aiReady =
          aiState.hasValue && !aiState.isLoading && !aiState.hasError;

      if (!cameraReady || !aiReady) return null;

      final controller = cameraState.value!;
      final aiService = aiState.value!;

      if (settings.autoScan) {
        if (!controller.value.isStreamingImages) {
          controller.startImageStream((image) {
            latestImage.value = image;

            if (isProcessing.value) return;

            final now = DateTime.now();
            // Reduced debounce from 800ms -> 200ms to allow smoother bounding box updates.
            // isProcessing acts as backpressure so frames aren't queued up.
            if (now.difference(lastAutoScanTime.value) <
                const Duration(milliseconds: 200)) {
              return;
            }
            lastAutoScanTime.value = now;
            isProcessing.value = true;

            aiService
                .predictFromCameraImage(
                  image,
                  controller.description.sensorOrientation,
                  settings.confidenceThreshold,
                )
                .then((prediction) {
              // FIX (H-04): guard against post-dispose state mutation.
              if (!isMounted()) return;

              final history = detectionHistory.value;

              if (prediction != null && prediction.isNotEmpty) {
                currentDetections.value = prediction;

                // ── 1. Parse labels and aggregate counts ──
                final Map<String, int> counts = {};
                double totalValue = 0;
                for (final p in prediction) {
                  counts[p.label] = (counts[p.label] ?? 0) + 1;
                  final match = RegExp(r'\d+').firstMatch(p.label);
                  if (match != null) {
                    totalValue += double.parse(match.group(0)!);
                  }
                }

                // ── 2. Sliding window consensus ──
                history.add(counts);
                if (history.length > 5) history.removeAt(0);

                bool isStable = history.length == 5;
                if (isStable) {
                  for (int i = 1; i < history.length; i++) {
                    if (!mapEquals(history[0], history[i])) {
                      isStable = false;
                      break;
                    }
                  }
                }

                // ── 3. Announce if stable and changed ──
                if (isStable) {
                  final parts = <String>[];
                  counts.forEach((label, count) {
                    parts.add('$count $label note${count > 1 ? 's' : ''}');
                  });
                  final summary = '${parts.join(', ')}. Total value: ${totalValue.toInt()} Ghana Cedis.';

                  scanStatus.value = 'Detected:\n${parts.join('\n')}\nTotal: GHS ${totalValue.toInt()}';
                  
                  if (lastSpokenText.value != summary) {
                    ref.read(speechServiceProvider).speak(summary);
                    lastSpokenText.value = summary;
                  }
                } else {
                  scanStatus.value = 'Verifying... (${history.length}/5)';
                }
              } else {
                currentDetections.value = [];
                // No detection: age out the oldest entry
                if (history.isNotEmpty) history.removeAt(0);
                if (history.isEmpty) {
                  scanStatus.value = 'Scanning...';
                  lastSpokenText.value = ''; // Reset so we announce again when notes return
                }
              }

              isProcessing.value = false;
            }).catchError((e) {
              if (!isMounted()) return;
              isProcessing.value = false;
              debugPrint('Auto-scan error: $e');
            });
          });
        }
      } else {
        // Auto-scan turned off — stop the stream and clear stale state.
        if (controller.value.isStreamingImages) {
          controller.stopImageStream().catchError((_) {});
          latestImage.value = null;
          detectionHistory.value.clear();
        }
      }

      return () {
        if (controller.value.isStreamingImages) {
          controller.stopImageStream().catchError((_) {});
        }
      };
    }, [
      cameraState.hasValue,
      aiState.hasValue,
      settings.autoScan,
      settings.confidenceThreshold,
    ]);

    // ── Convenience booleans for the UI ──
    final cameraLoading = cameraState.isLoading;
    final cameraError = cameraState.hasError;
    final aiLoading = aiState.isLoading;
    final aiError = aiState.hasError;
    final systemBusy = cameraLoading || cameraError || aiLoading || aiError;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── 1. Full-screen camera preview ──
          Positioned.fill(
            child: cameraState.when(
              data: (controller) => Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Colors.black,
                    child: Center(child: CameraPreview(controller)),
                  ),
                  ValueListenableBuilder<List<RecognizedObject>>(
                    valueListenable: currentDetections,
                    builder: (context, detections, _) {
                      return BoundingBoxOverlay(
                        cameraController: controller,
                        detections: detections,
                      );
                    },
                  ),
                ],
              ),
              error: (error, _) => _buildCameraError(
                context,
                theme,
                error,
                ref,
              ),
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Initialising camera...',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 2. Top-right floating buttons ──
          Positioned(
            top: MediaQuery.paddingOf(context).top + 16,
            right: 16,
            child: Column(
              children: [
                // Settings
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white),
                    tooltip: 'Settings',
                    iconSize: 28,
                    onPressed: () => context.push('/settings'),
                  ),
                ),
                const SizedBox(height: 16),

                // Torch (only shown when camera is ready)
                if (cameraState.hasValue &&
                    !cameraState.isLoading &&
                    !cameraState.hasError)
                  Container(
                    decoration: BoxDecoration(
                      color: isFlashOn.value
                          ? theme.colorScheme.primary
                          : Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        isFlashOn.value ? Icons.flash_on : Icons.flash_off,
                        color: isFlashOn.value
                            ? theme.colorScheme.onPrimary
                            : Colors.white,
                      ),
                      tooltip: 'Toggle Flashlight',
                      iconSize: 28,
                      onPressed: () async {
                        final controller = cameraState.value!;
                        try {
                          final newMode = isFlashOn.value
                              ? FlashMode.off
                              : FlashMode.torch;
                          await controller.setFlashMode(newMode);
                          if (isMounted()) isFlashOn.value = !isFlashOn.value;
                        } catch (e) {
                          debugPrint('Failed to toggle flash: $e');
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ── 3. AI model loading overlay ──
          if (aiLoading)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 16,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Loading AI model...',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // ── 4. Bottom interaction panel ──
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
                    color: theme.colorScheme.surface.withValues(alpha: 0.75),
                    border: Border(
                      top: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status text
                      Text(
                        scanStatus.value,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        semanticsLabel: 'Status: ${scanStatus.value}',
                      ),
                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        children: [
                          // ── SCAN NOTE ──
                          Expanded(
                            child: SizedBox(
                              height: 72,
                              child: ElevatedButton.icon(
                                onPressed:
                                    systemBusy || isProcessing.value
                                        ? null
                                        : () async {
                                            if (!isMounted()) return;
                                            isProcessing.value = true;
                                            scanStatus.value = 'Scanning note...';

                                            final speechService = ref
                                                .read(speechServiceProvider);
                                            await speechService.speak(
                                              'Scanning note. Please hold steady.',
                                            );

                                            try {
                                              final controller =
                                                  cameraState.value!;
                                              final aiService =
                                                  aiState.value!;
                                              List<RecognizedObject>? prediction;

                                              if (!isMounted()) return;
                                              scanStatus.value = 'Analysing...';

                                              if (settings.autoScan) {
                                                // Use the most recent stream frame.
                                                final image =
                                                    latestImage.value;
                                                if (image == null) {
                                                  throw Exception(
                                                    'No camera frame ready yet.',
                                                  );
                                                }
                                                prediction = await aiService
                                                    .predictFromCameraImage(
                                                  image,
                                                  controller.description
                                                      .sensorOrientation,
                                                  settings.confidenceThreshold,
                                                );
                                              } else {
                                                // Take a still picture.
                                                final xFile = await controller
                                                    .takePicture();
                                                prediction = await aiService
                                                    .predict(
                                                  xFile.path,
                                                  settings.confidenceThreshold,
                                                );
                                              }

                                              if (!isMounted()) return;
                                              if (prediction != null && prediction.isNotEmpty) {
                                                final Map<String, int> counts = {};
                                                double totalValue = 0;
                                                for (final p in prediction) {
                                                  counts[p.label] = (counts[p.label] ?? 0) + 1;
                                                  final match = RegExp(r'\d+').firstMatch(p.label);
                                                  if (match != null) {
                                                    totalValue += double.parse(match.group(0)!);
                                                  }
                                                }

                                                final parts = <String>[];
                                                counts.forEach((label, count) {
                                                  parts.add('$count $label note${count > 1 ? 's' : ''}');
                                                });
                                                final summary = '${parts.join(', ')}. Total value: ${totalValue.toInt()} Ghana Cedis.';

                                                scanStatus.value = 'Detected:\n${parts.join('\n')}\nTotal: GHS ${totalValue.toInt()}';
                                                await speechService.speak(summary);
                                              } else {
                                                scanStatus.value =
                                                    'Could not detect note.';
                                                await speechService.speak(
                                                  'Could not clearly detect the note. '
                                                  'Please ensure the note is well lit '
                                                  'and centred in the camera.',
                                                );
                                              }
                                            } catch (e) {
                                              if (!isMounted()) return;
                                              scanStatus.value = 'Scan failed.';
                                              await ref
                                                  .read(speechServiceProvider)
                                                  .speak(
                                                    'An error occurred during scan.',
                                                  );
                                              debugPrint(
                                                'Manual scan error: $e',
                                              );
                                            } finally {
                                              if (isMounted()) {
                                                isProcessing.value = false;
                                              }
                                            }
                                          },
                                icon: const Icon(
                                  Icons.document_scanner,
                                  size: 28,
                                ),
                                label: const Text('SCAN NOTE'),
                                style: ElevatedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
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

  // ---------------------------------------------------------------------------
  // Camera error widget — accessible message with TTS and settings link
  // ---------------------------------------------------------------------------

  Widget _buildCameraError(
    BuildContext context,
    ThemeData theme,
    Object error,
    WidgetRef ref,
  ) {
    final isPermissionError = error.toString().toLowerCase().contains('permiss');

    // Announce the error via TTS for visually impaired users.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(speechServiceProvider).speak(
            isPermissionError
                ? 'Camera permission denied. Please grant camera access in Settings.'
                : 'Camera unavailable. Please restart the application.',
          );
    });

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPermissionError ? Icons.no_photography : Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              isPermissionError
                  ? 'Camera permission denied.\nPlease grant access in Settings.'
                  : 'Camera unavailable.\n${error.toString()}',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            if (isPermissionError) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
