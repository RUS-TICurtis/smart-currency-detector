import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_hooks/flutter_hooks.dart';

import 'providers/camera_provider.dart';
import 'providers/ai_provider.dart';
import '../speech/providers/speech_provider.dart';

class CameraScreen extends HookConsumerWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cameraState = ref.watch(cameraControllerProvider);
    final scanStatus = useState('Ready to scan');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Currency Detector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            iconSize: 32,
            onPressed: () {
              context.push('/settings');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Camera Preview Section
            Expanded(
              flex: 3,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: cameraState.when(
                    data: (controller) => CameraPreview(controller),
                    error: (error, stackTrace) => Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 60,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text(
                              'Failed to load camera:\n$error',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: 'Loading camera feed',
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Interaction Area
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      scanStatus.value,
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                      semanticsLabel: 'Status: ${scanStatus.value}',
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 80, // Extra large tap target
                      child: ElevatedButton.icon(
                        onPressed: cameraState.isLoading || cameraState.hasError 
                          ? null 
                          : () async {
                              final speechService = ref.read(speechServiceProvider);
                              final aiService = ref.read(aiServiceProvider);
                              
                              scanStatus.value = 'Scanning note...';
                              await speechService.speak('Scanning note. Please hold the camera steady.');
                              
                              try {
                                final xFile = await cameraState.value!.takePicture();
                                scanStatus.value = 'Analyzing...';
                                
                                final prediction = await aiService.predict(xFile.path);
                                
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
                              }
                          },
                        icon: const Icon(Icons.document_scanner, size: 36),
                        label: const Text('SCAN NOTE'),
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
