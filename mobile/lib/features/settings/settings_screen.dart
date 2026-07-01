import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'providers/settings_provider.dart';
import '../speech/providers/speech_provider.dart';

class SettingsScreen extends HookConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final speechService = ref.read(speechServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accessibility Preferences',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 32),
              
              // Speech Rate Slider
              Text(
                'Speech Rate',
                style: theme.textTheme.titleLarge,
                semanticsLabel: 'Speech Rate Adjustment',
              ),
              Row(
                children: [
                  const Icon(Icons.speed, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      value: settings.speechRate,
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      label: settings.speechRate.toStringAsFixed(1),
                      onChanged: (value) {
                        settingsNotifier.updateSpeechRate(value);
                      },
                      onChangeEnd: (value) {
                        speechService.speak('Speech rate updated');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Speech Volume Slider
              Text(
                'Speech Volume',
                style: theme.textTheme.titleLarge,
                semanticsLabel: 'Speech Volume Adjustment',
              ),
              Row(
                children: [
                  const Icon(Icons.volume_up, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      value: settings.speechVolume,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      label: settings.speechVolume.toStringAsFixed(1),
                      onChanged: (value) {
                        settingsNotifier.updateSpeechVolume(value);
                      },
                      onChangeEnd: (value) {
                        speechService.speak('Volume updated');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Camera Zoom Slider
              Text(
                'Camera Zoom',
                style: theme.textTheme.titleLarge,
                semanticsLabel: 'Camera Zoom Adjustment',
              ),
              Row(
                children: [
                  const Icon(Icons.zoom_in, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      value: settings.cameraZoom,
                      min: 1.0,
                      max: 3.0,
                      divisions: 8,
                      label: '${settings.cameraZoom.toStringAsFixed(1)}x',
                      onChanged: (value) {
                        settingsNotifier.updateCameraZoom(value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Confidence Threshold Slider
              Text(
                'AI Strictness (Confidence)',
                style: theme.textTheme.titleLarge,
                semanticsLabel: 'AI Strictness Adjustment',
              ),
              Text(
                'Higher strictness prevents false positives but may require better lighting.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.analytics, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      value: settings.confidenceThreshold,
                      min: 0.5,
                      max: 0.95,
                      divisions: 9,
                      label: '${(settings.confidenceThreshold * 100).round()}%',
                      onChanged: (value) {
                        settingsNotifier.updateConfidenceThreshold(value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Auto-Scan Toggle
              Text(
                'Auto-Scan Mode',
                style: theme.textTheme.titleLarge,
                semanticsLabel: 'Auto-Scan Mode Toggle',
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Automatically detect notes without pressing a button. This uses more battery.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Switch(
                    value: settings.autoScan,
                    onChanged: (value) {
                      settingsNotifier.updateAutoScan(value);
                      if (value) {
                        speechService.speak('Auto scan enabled');
                      } else {
                        speechService.speak('Auto scan disabled');
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
