import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/session_provider.dart';

class SummationBottomSheet extends ConsumerWidget {
  const SummationBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionProvider);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Current Session',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                semanticsLabel: 'Current Session Summary',
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.pop(),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Total Value Big Text
          Center(
            child: Text(
              'GHS ${sessionState.totalValue.toStringAsFixed(2)}',
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
              semanticsLabel: 'Total value: ${sessionState.totalValue.toStringAsFixed(2)} Ghana Cedis',
            ),
          ),
          Center(
            child: Text(
              'Total Items: ${sessionState.totalNotes}',
              style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 24),

          // Breakdown List
          if (sessionState.denominationCounts.isNotEmpty) ...[
            Text(
              'Breakdown',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sessionState.denominationCounts.length,
                itemBuilder: (context, index) {
                  final entry = sessionState.denominationCounts.entries.elementAt(index);
                  final denomination = entry.key;
                  final count = entry.value;
                  final totalForDenom = denomination.value * count;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${denomination.displayName} x $count'),
                    trailing: Text(
                      'GHS ${totalForDenom.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sessionState.items.isEmpty ? null : () {
                    ref.read(sessionProvider.notifier).clearSession();
                    context.pop();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear All'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: sessionState.items.isEmpty ? null : () async {
                    await ref.read(sessionProvider.notifier).saveSessionToHistory();
                    if (context.mounted) {
                      context.pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Session saved to history')),
                      );
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save Session'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
