import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend/build_backend.dart';
import '../../state/build_controller.dart';
import '../../widgets/section_card.dart';

/// Switch for the additional unsigned .ipa (GitHub Actions on macOS).
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
      child = const Text('Сборка для iPhone доступна в режиме «GitHub Actions»: для неё нужен macOS с Xcode, '
          'а он есть только там.');
    } else if (!c.isWeb) {
      child = const Text('Для iPhone собираются только веб-проекты (HTML/JS, React, Vue, Vite). '
          'Код Kotlin/Java работает только на Android.');
    } else {
      child = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: c.buildIos,
          onChanged: c.busy ? null : c.setBuildIos,
          title: const Text('Собрать также .ipa для iPhone'),
          subtitle: const Text('Неподписанный .ipa: ставится с компьютера через Sideloadly под вашим Apple ID.'),
        ),
        Text(
          'Сборка на macOS добавляет 3–6 минут. В приватном репозитории минуты macOS расходуются в 10 раз быстрее.',
          style: muted,
        ),
      ]);
    }
    return SectionCard(title: 'iPhone (iOS)', icon: Icons.phone_iphone, child: child);
  }
}
