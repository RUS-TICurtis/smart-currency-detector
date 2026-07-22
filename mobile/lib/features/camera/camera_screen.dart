import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'package:permission_handler/permission_handler.dart';

import 'providers/camera_provider.dart';
import 'providers/ai_provider.dart';
import 'widgets/bounding_box_overlay.dart';
import '../../../core/services/ai_model_service.dart';
import '../../../core/models/ghana_cedi_denomination.dart';
import '../../../core/services/currency_validator.dart';
import '../speech/providers/speech_provider.dart';
import '../speech/providers/voice_guidance_provider.dart';
import '../settings/providers/settings_provider.dart';
import '../detection/providers/session_provider.dart';
import '../detection/widgets/summation_bottom_sheet.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
 
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
    final voiceGuidance = ref.watch(voiceGuidanceProvider);

    // Play orientation on initial launch
    useEffect(() {
      voiceGuidance.playOrientation();
      return null;
    }, const []);

    // ── Local state ──
    final scanStatus = useState<String>('Starting camera...');
    final snapshotBytes = useState<Uint8List?>(null);
    final isProcessing = useState(false);
    final isFlashOn = useState(false);
    final appResumedTick = useState(0);

    // BUG-08 FIX: Use useRef<bool> so the disposed flag persists across
    // rebuilds. A plain local 'bool disposed' creates a NEW instance on
    // every build() call — the useEffect cleanup sets the OLD copy to true,
    // but callbacks on the new build check the NEW copy (always false),
    // allowing post-dispose code to run and causing setState-on-disposed errors.
    final disposed = useRef(false);
    useEffect(() {
      return () { disposed.value = true; };
    }, const []);
    bool isMounted() => !disposed.value;

    // Internal refs — mutations don't need to trigger a rebuild.
    final latestImage = useRef<CameraImage?>(null);
    final lastAutoScanTime = useRef<DateTime>(DateTime.now());
    
    // Aggregation history for multi-note detection.
    final detectionHistory = useRef<List<Map<GhanaCedi, int>>>([]);
    // BUG-09 FIX: Tracks consecutive 5-frame windows that returned no stable
    // detection. resetScannerTracking() is only called after 3 consecutive
    // empty windows (~3 seconds), preventing a brief note repositioning from
    // clearing the cooldown guard and triggering a double-count.
    final consecutiveEmptyWindows = useRef(0);
    
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
          
          // Stop stream and torch, but DO NOT invalidate provider.
          // Native camera plugin can resume itself, provider rebuild causes jank.
        },
        onResume: () {
          // The autoScan effect (Effect 3) will restart the stream if needed.
          debugPrint('CameraScreen: app resumed.');
          if (isMounted()) appResumedTick.value++;
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

              final Map<GhanaCedi, int> counts = prediction != null && prediction.isNotEmpty
                  ? CurrencyValidator.validateAndCapDetections(prediction)
                  : {};

              if (prediction != null && prediction.isNotEmpty) {
                currentDetections.value = prediction;
              } else {
                // Anti-flicker: Only clear bounding boxes if the previous 2 frames were also empty
                // (3 empty frames total = 600ms grace period)
                int emptyCount = 0;
                for (int i = history.length - 1; i >= 0; i--) {
                  if (history[i].isEmpty) {
                    emptyCount++;
                  } else {
                    break;
                  }
                }
                if (emptyCount >= 2) {
                  currentDetections.value = [];
                }
              }

              // ── 2. Sliding window Median Consensus ──
              history.add(counts);
              if (history.length > 5) history.removeAt(0);

              // Wait until we have a full window (5 frames) for a stable read
              if (history.length == 5) {
                final Map<GhanaCedi, int> stableCounts = {};
                final Set<GhanaCedi> allLabels = {};
                for (final map in history) {
                  allLabels.addAll(map.keys);
                }

                for (final denomination in allLabels) {
                  // Extract counts for this label across all 5 frames
                  final labelCounts = history.map((m) => m[denomination] ?? 0).toList();
                  labelCounts.sort();
                  final median = labelCounts[2]; // middle element of 5
                  
                  if (median > 0) {
                    stableCounts[denomination] = median;
                  }
                }

                // ── 3. Process with SessionProvider ──
                if (stableCounts.isNotEmpty) {
                  consecutiveEmptyWindows.value = 0;
                  final addedItems = ref.read(sessionProvider.notifier).addDetections(stableCounts);
                  
                  if (addedItems.isNotEmpty) {
                    Haptics.vibrate(HapticsType.success);
                    final firstItem = addedItems.first;
                    voiceGuidance.announceScanSuccess(firstItem.spokenValue);
                    scanStatus.value = '${firstItem.spokenValue} detected.\nScan again to add another.';
                  }
                } else {
                  consecutiveEmptyWindows.value++;
                  if (consecutiveEmptyWindows.value >= 15) {
                    consecutiveEmptyWindows.value = 0;
                    scanStatus.value = 'Searching for currency...';
                  } else if (scanStatus.value.startsWith('Verifying') || scanStatus.value == 'Ready to scan') {
                    scanStatus.value = 'Searching for notes & coins...';
                  }
                }
              } else {
                scanStatus.value = 'Verifying... (${history.length}/5)';
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
      appResumedTick.value,
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
                    width: double.infinity,
                    height: double.infinity,
                    color: Colors.black,
                    child: Center(child: RepaintBoundary(child: CameraPreview(controller))),
                  ),
                  if (!settings.autoScan && snapshotBytes.value != null)
                    Positioned.fill(
                      child: Image.memory(
                        snapshotBytes.value!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  RepaintBoundary(
                    child: ValueListenableBuilder<List<RecognizedObject>>(
                      valueListenable: currentDetections,
                      builder: (context, detections, _) {
                        return BoundingBoxOverlay(
                          cameraController: controller,
                          detections: detections,
                        );
                      },
                    ),
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
                // History
                Semantics(
                  button: true,
                  label: 'History',
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.history, color: Colors.white),
                      tooltip: 'History',
                      iconSize: 28,
                      onPressed: () => context.push('/history'),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Settings
                Semantics(
                  button: true,
                  label: 'Settings',
                  child: Container(
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
                ),
                const SizedBox(height: 16),

                // Torch (only shown when camera is ready)
                if (cameraState.hasValue &&
                    !cameraState.isLoading &&
                    !cameraState.hasError)
                  Semantics(
                    button: true,
                    label: isFlashOn.value ? 'Turn off flashlight' : 'Turn on flashlight',
                    child: Container(
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
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // ── 1. CLEAR BUTTON ──
                          Expanded(
                            child: SizedBox(
                              height: 104,
                              child: OutlinedButton(
                                onPressed: isProcessing.value
                                    ? null
                                    : () {
                                        final removed = ref.read(sessionProvider.notifier).removeLastItem();
                                        final session = ref.read(sessionProvider);
                                        final isNowEmpty = session.items.isEmpty;
                                        final spokenNewTotal = GhanaCedi.formatSpokenTotal(session.totalValue);
                                        
                                        voiceGuidance.announceItemRemoved(
                                          removed?.spokenValue,
                                          spokenNewTotal,
                                          isNowEmpty,
                                        );
                                        
                                        if (removed != null) {
                                          Haptics.vibrate(HapticsType.selection);
                                          scanStatus.value = 'Removed ${removed.spokenValue}';
                                        } else {
                                          scanStatus.value = 'Nothing to remove.';
                                        }
                                      },
                                onLongPress: isProcessing.value
                                    ? null
                                    : () async {
                                        await voiceGuidance.announceSessionCleared(true);
                                        ref.read(sessionProvider.notifier).clearSession();
                                        voiceGuidance.resetSession();
                                        Haptics.vibrate(HapticsType.medium);
                                        await voiceGuidance.announceSessionCleared(false);
                                        scanStatus.value = 'Session cleared';
                                      },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: theme.colorScheme.error,
                                  side: BorderSide(color: theme.colorScheme.error),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.backspace, size: 28),
                                    SizedBox(height: 8),
                                    Text(
                                      'Clear',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // ── 2. SUM BUTTON ──
                          Expanded(
                            child: SizedBox(
                              height: 104,
                              child: ElevatedButton(
                                onPressed: () {
                                  final session = ref.read(sessionProvider);
                                  final spokenTotal = GhanaCedi.formatSpokenTotal(session.totalValue);
                                  voiceGuidance.announceSum(session.items.length, spokenTotal);
                                  
                                  if (session.items.isEmpty) {
                                    scanStatus.value = 'No currency stored';
                                  } else {
                                    Haptics.vibrate(HapticsType.medium);
                                    scanStatus.value = 'Total: GHS ${session.totalValue.toStringAsFixed(2)}';
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.functions, size: 30),
                                    SizedBox(height: 8),
                                    Text(
                                      'Sum',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // ── 3. SCAN BUTTON ──
                          Expanded(
                            child: SizedBox(
                              height: 104,

                              child: ElevatedButton(
                                onPressed: systemBusy || isProcessing.value
                                    ? null
                                    : () async {
                                        if (!isMounted()) return;
                                        isProcessing.value = true;
                                        scanStatus.value = 'Scanning...';
                                        currentDetections.value = [];
                                        snapshotBytes.value = null;

                                        final speechService = ref.read(speechServiceProvider);
                                        speechService.speak('Scanning.');

                                        try {
                                          final controller = cameraState.value!;
                                          final aiService = aiState.value!;
                                          List<RecognizedObject>? prediction;

                                          if (!isMounted()) return;
                                          scanStatus.value = 'Analysing...';

                                          if (settings.autoScan && latestImage.value != null) {
                                            prediction = await aiService.predictFromCameraImage(
                                              latestImage.value!,
                                              controller.description.sensorOrientation,
                                              settings.confidenceThreshold,
                                            );
                                          } else {
                                            final xFile = await controller.takePicture();
                                            final bytes = await xFile.readAsBytes();
                                            if (isMounted()) snapshotBytes.value = bytes;

                                            prediction = await aiService.predict(
                                              xFile.path,
                                              settings.confidenceThreshold,
                                            );
                                          }

                                          if (!isMounted()) return;

                                          if (prediction != null && prediction.isNotEmpty) {
                                            final validatedCounts = CurrencyValidator.validateAndCapDetections(prediction);
                                            
                                            if (validatedCounts.isNotEmpty) {
                                              final addedItems = ref.read(sessionProvider.notifier).addDetections(validatedCounts);
                                              Haptics.vibrate(HapticsType.success);

                                              final firstItem = addedItems.first;
                                              voiceGuidance.announceScanSuccess(firstItem.spokenValue);
                                              scanStatus.value = '${firstItem.spokenValue} detected.\nScan again to add another currency.';
                                            } else {
                                              scanStatus.value = 'Could not detect valid currency.';
                                              await voiceGuidance.announceScanFailure();
                                            }
                                          } else {
                                            scanStatus.value = 'Could not detect currency.';
                                            await voiceGuidance.announceScanFailure();
                                          }
                                        } catch (e) {
                                          if (!isMounted()) return;
                                          scanStatus.value = 'Scan failed.';
                                          await speechService.speak('An error occurred during scan. Try again.');
                                        } finally {
                                          if (isMounted()) {
                                            isProcessing.value = false;
                                            snapshotBytes.value = null;
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.document_scanner, size: 36),
                                    SizedBox(height: 8),
                                    Text(
                                      'Scan',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
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
