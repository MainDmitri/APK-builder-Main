import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/build_controller.dart';
import '../../widgets/section_card.dart';

/// Launcher icon of the built app: the project's own icon, a picture chosen
/// here, or a generated letter icon when there is none.
class IconSection extends StatelessWidget {
  const IconSection({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BuildController>();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final projectIcon = c.projectIcon;

    final String description;
    if (c.isNativeGradle) {
      description = 'Gradle-проект: иконка берётся из ресурсов самого проекта.';
    } else if (c.icon != null) {
      description = 'Выбрана картинка «${c.icon!.name}» — она заменит иконку проекта.';
    } else if (projectIcon != null) {
      description = projectIcon.predicted
          ? 'Иконка проекта: ${projectIcon.path} (попадёт в сборку из папки public).'
          : 'Иконка проекта: ${projectIcon.path}.';
    } else {
      description = 'В проекте нет иконки — будет создана буква на цвете темы. Можно выбрать свою картинку.';
    }

    return SectionCard(
      title: 'Иконка приложения',
      icon: Icons.image_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
                child: _Preview(key: ValueKey(c.icon?.name ?? projectIcon?.path ?? 'letter'), controller: c),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(description),
                  const SizedBox(height: 4),
                  if (!c.isNativeGradle) Text('PNG, JPEG или WebP, лучше квадрат от 512×512.', style: muted),
                ]),
              ),
            ],
          ),
          if (c.iconError != null) ...[
            const SizedBox(height: 10),
            MessageList(messages: [c.iconError!], error: true),
          ],
          if (!c.isNativeGradle) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(
                onPressed: c.buildRunning ? null : c.pickIcon,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(c.icon == null ? 'Выбрать картинку' : 'Заменить'),
              ),
              if (c.icon != null)
                TextButton.icon(
                  onPressed: c.buildRunning ? null : c.clearIcon,
                  icon: const Icon(Icons.close),
                  label: const Text('Убрать'),
                ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({super.key, required this.controller});

  final BuildController controller;

  static Color _parse(String hex) =>
      Color(int.tryParse('FF${hex.replaceFirst('#', '').padRight(6, '0').substring(0, 6)}', radix: 16) ?? 0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final bytes = c.icon?.bytes ?? c.projectIconBytes;
    final Widget content;
    if (bytes != null) {
      content = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => _fallback(context));
    } else if (c.projectIcon != null) {
      // SVG / adaptive XML: Flutter cannot preview it without extra packages.
      content = _fallback(context, label: c.projectIcon!.path.split('.').last.toUpperCase());
    } else {
      final background = _parse(c.themeColor);
      final light = background.computeLuminance() > 0.6;
      final letter = RegExp(r'[\p{L}\p{N}]', unicode: true).firstMatch(c.appName.text)?.group(0)?.toUpperCase() ?? 'A';
      content = Container(
        color: background,
        alignment: Alignment.center,
        child: Text(letter,
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: light ? const Color(0xFF212121) : Colors.white)),
      );
    }
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _fallback(BuildContext context, {String? label}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.image_outlined, color: scheme.onSurfaceVariant),
        if (label != null) Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}
