import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend/build_backend.dart';
import '../../services/transfer/transfer_models.dart';
import '../../state/downloads_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/section_card.dart';
import 'apk_panel.dart';

/// The iPhone part of a build: macOS build progress, .ipa download with
/// progress and how to install it with Sideloadly.
class IpaPanel extends StatelessWidget {
  const IpaPanel({super.key, required this.backend, required this.buildId, required this.info});

  final BuildBackend backend;
  final String buildId;
  final IosBuildInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final Widget body = switch (info.state) {
      IosBuildState.pending => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Сборка для iPhone на macOS…', style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          const GradientProgressBar(value: null),
          const SizedBox(height: 6),
          Text('Веб-проект — 3–6 минут после APK, Flutter — 8–15. Статус обновляется сам.', style: muted),
        ]),
      IosBuildState.failed => NoticeBox(
          text: info.error ?? 'Сборка для iPhone не удалась.',
          color: theme.colorScheme.error,
          icon: Icons.error_outline,
        ),
      IosBuildState.succeeded => _Ready(backend: backend, buildId: buildId, info: info),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.phone_iphone, color: AppColors.cyan, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(info.fileName ?? 'iPhone (.ipa)', style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
            Text(
              [if (info.size != null) formatBytes(info.size!), 'без подписи — ставится через Sideloadly'].join(' · '),
              style: muted,
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: KeyedSubtree(key: ValueKey(info.state), child: body)),
    ]);
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.backend, required this.buildId, required this.info});

  final BuildBackend backend;
  final String buildId;
  final IosBuildInfo info;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DownloadsController>();
    final job = d.job(buildId, kind: ArtifactKind.ipa);
    final Widget action;
    if (job == null) {
      action = OutlinedButton.icon(
        onPressed: () => d.download(backend, buildId, kind: ArtifactKind.ipa),
        icon: const Icon(Icons.download_rounded),
        label: const Text('Скачать .ipa'),
      );
    } else if (job.active) {
      action = DownloadProgressView(
        job: job,
        onCancel: () => d.cancel(buildId, kind: ArtifactKind.ipa),
        backgroundHint: d.canInstall,
      );
    } else if (job.phase == TransferPhase.failed) {
      action = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        NoticeBox(text: job.message ?? 'Не удалось скачать .ipa.', color: Theme.of(context).colorScheme.error),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => d.download(backend, buildId, kind: ArtifactKind.ipa),
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить'),
        ),
      ]);
    } else {
      action = FilledButton.icon(
        onPressed: () async {
          final message = await d.save(buildId, kind: ArtifactKind.ipa);
          if (context.mounted) showSnack(context, message);
        },
        icon: const Icon(Icons.save_alt),
        label: const Text('Сохранить .ipa'),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      action,
      const SizedBox(height: 4),
      const _SideloadGuide(),
    ]);
  }
}

/// Installing an unsigned .ipa with a free Apple ID.
class _SideloadGuide extends StatelessWidget {
  const _SideloadGuide();

  static const _steps = [
    'Перенесите .ipa на компьютер с Windows или macOS и установите Sideloadly (sideloadly.io). '
        'На Windows также нужны iTunes и iCloud с сайта Apple — не из Microsoft Store.',
    'Подключите iPhone кабелем и на телефоне нажмите «Доверять этому компьютеру».',
    'Перетащите .ipa в окно Sideloadly, введите свой Apple ID (подойдёт бесплатный) и нажмите Start.',
    'На iPhone: Настройки → Основные → VPN и управление устройством → ваш Apple ID → «Доверять».',
    'iOS 16 и новее: Настройки → Конфиденциальность и безопасность → Режим разработчика → включить, '
        'затем перезагрузить iPhone.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Как установить на iPhone'),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final (i, step) in _steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: AppColors.violet,
                child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(step)),
            ]),
          ),
        const SizedBox(height: 6),
        Text(
          'С бесплатным Apple ID приложение работает 7 дней — потом установите его снова '
          '(Sideloadly умеет обновлять автоматически по Wi-Fi). Одновременно — не больше 3 таких приложений.',
          style: muted,
        ),
      ],
    );
  }
}
