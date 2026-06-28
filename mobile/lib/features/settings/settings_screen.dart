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
            ],
          ),
        ),
      ),
    );
  }
}
