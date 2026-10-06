import 'package:flutter/material.dart';

/// Titled card used for every block of the screens.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.icon, required this.child, this.trailing});

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// List of warnings / errors with an icon per line.
class MessageList extends StatelessWidget {
  const MessageList({super.key, required this.messages, required this.error});

  final List<String> messages;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = error ? scheme.error : const Color(0xFFB26A00);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final m in messages)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(error ? Icons.error_outline : Icons.warning_amber_rounded, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(child: SelectableText(m)),
              ],
            ),
          ),
      ],
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} МБ';
}
