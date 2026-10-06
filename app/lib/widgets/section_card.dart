import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'motion.dart';

/// Titled card used for every block of the screens; its content animates
/// its size when it changes.
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
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GradientBadge(icon: icon, size: 36),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: child,
            ),
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
    final color = error ? scheme.error : AppColors.warning;
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

/// Tinted box for a single important message (error, hint).
class NoticeBox extends StatelessWidget {
  const NoticeBox({super.key, required this.text, required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, color: color, size: 20), const SizedBox(width: 10)],
          Expanded(child: SelectableText(text)),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
}

String formatDuration(Duration d) {
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}
