import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend/build_backend.dart';
import '../../state/build_controller.dart';
import '../../widgets/section_card.dart';

/// What to build: APK, APK + unsigned .ipa or only the .ipa (GitHub Actions on macOS).
class IosSection extends StatelessWidget {
  const IosSection({super.key, required this.backend});

  final BuildBackend? backend;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BuildController>();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final Widget child;
    if (!(backend?.supportsIos ?? false)) {
      child = const Text('Собирается APK для Android. Сборка для iPhone доступна в режиме «GitHub Actions»: '
          'для неё нужен macOS с Xcode, а он есть только там.');
    } else if (!(c.analysis?.kind.supportsIos ?? false)) {
      child = const Text('Собирается APK для Android. Для iPhone собираются веб-проекты (HTML/JS, React, Vue, Vite) '
          'и Flutter. Код Kotlin/Java работает только на Android.');
    } else {
      final target = c.targetFor(backend);
      child = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<BuildTarget>(
          showSelectedIcon: false,
          segments: [
            for (final t in BuildTarget.values) ButtonSegment(value: t, label: Text(t.title, maxLines: 1, softWrap: false)),
          ],
          selected: {target},
          onSelectionChanged: c.busy ? null : (s) => c.setTarget(s.first),
        ),
        const SizedBox(height: 12),
        Text(switch (target) {
          BuildTarget.apk => 'Только Android: подписанный APK, без macOS.',
          BuildTarget.both => 'APK скачается сразу, .ipa для iPhone появится позже. '
              'Неподписанный .ipa ставится с компьютера через Sideloadly под вашим Apple ID.',
          BuildTarget.ipa => 'Только .ipa для iPhone: APK не собирается, подпись Android не нужна. '
              'Неподписанный .ipa ставится с компьютера через Sideloadly под вашим Apple ID.',
        }),
        if (target.ipaWanted) ...[
          const SizedBox(height: 6),
          Text(
            'Сборка на macOS занимает ${c.isFlutter ? '8–15' : '3–6'} минут. '
            'В приватном репозитории минуты macOS расходуются в 10 раз быстрее.',
            style: muted,
          ),
        ],
      ]);
    }
    return SectionCard(title: 'Платформа', icon: Icons.devices_rounded, child: child);
  }
}
