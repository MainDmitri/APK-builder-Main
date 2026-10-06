import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend/build_backend.dart';
import '../../services/transfer/transfer_models.dart';
import '../../state/downloads_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/section_card.dart';

/// Download progress, installation progress and actions for the APK of one
/// successful build. Used on the build screen and in the history.
class ApkPanel extends StatelessWidget {
  const ApkPanel({super.key, required this.backend, required this.buildId, this.compact = false});

  final BuildBackend backend;
  final String buildId;

  /// History rows: smaller buttons, no big call-to-action.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DownloadsController>();
    final job = d.job(buildId);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, alignment: Alignment.topCenter, child: child),
      ),
      child: KeyedSubtree(
        key: ValueKey('${job?.phase}-${job?.install}'),
        child: job == null ? _start(context, d) : _job(context, d, job),
      ),
    );
  }

  Widget _start(BuildContext context, DownloadsController d) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (d.canInstall)
        FilledButton.icon(
          onPressed: () => d.download(backend, buildId, thenInstall: true),
          icon: const Icon(Icons.install_mobile),
          label: const Text('Скачать и установить'),
        ),
      OutlinedButton.icon(
        onPressed: () => d.download(backend, buildId),
        icon: const Icon(Icons.download_rounded),
        label: const Text('Скачать APK'),
      ),
    ]);
  }

  Widget _job(BuildContext context, DownloadsController d, ApkJob job) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    switch (job.phase) {
      case TransferPhase.queued:
      case TransferPhase.downloading:
      case TransferPhase.paused:
        final paused = job.phase == TransferPhase.paused;
        final percent = job.fraction == null ? '' : '${(job.fraction! * 100).floor()}%';
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(
                job.phase == TransferPhase.queued ? 'Подготовка загрузки…' : (paused ? 'Пауза' : 'Скачивание APK'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(percent, style: theme.textTheme.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 10),
          GradientProgressBar(
            value: job.phase == TransferPhase.queued ? null : job.fraction,
            color: paused ? AppColors.warning : null,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Text(
                [
                  job.total == null ? formatBytes(job.received) : '${formatBytes(job.received)} из ${formatBytes(job.total!)}',
                  if (job.speed > 0 && !paused) '${formatBytes(job.speed)}/с',
                  if (job.remaining case final r?) 'осталось ${_short(r)}',
                ].join(' · '),
                style: muted,
              ),
            ),
            TextButton(onPressed: () => d.cancel(buildId), child: const Text('Отменить')),
          ]),
          if (paused && job.message != null) Text(job.message!, style: muted?.copyWith(color: AppColors.warning)),
          if (d.canInstall)
            Text('Загрузка продолжится в фоне, даже если свернуть AppBuilder.', style: muted),
        ]);
      case TransferPhase.failed:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoticeBox(text: job.message ?? 'Не удалось скачать APK.', color: theme.colorScheme.error, icon: Icons.error_outline),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => d.download(backend, buildId),
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ),
        ]);
      case TransferPhase.done:
        return _downloaded(context, d, job, muted);
    }
  }

  Widget _downloaded(BuildContext context, DownloadsController d, ApkJob job, TextStyle? muted) {
    final theme = Theme.of(context);
    final header = Row(children: [
      const Icon(Icons.android, color: AppColors.success, size: 30),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(job.fileName ?? 'app.apk', style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis),
          Text('${formatBytes(job.received)} · скачан', style: muted),
        ]),
      ),
    ]);
    final save = OutlinedButton.icon(
      onPressed: () async {
        final message = await d.save(buildId);
        if (context.mounted) showSnack(context, message);
      },
      icon: const Icon(Icons.save_alt),
      label: const Text('Сохранить APK'),
    );

    final Widget body = switch (job.install) {
      null when !d.canInstall => save,
      null => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          compact
              ? FilledButton.icon(
                  onPressed: () => d.install(buildId),
                  icon: const Icon(Icons.install_mobile),
                  label: const Text('Установить'),
                )
              : GradientButton(label: 'Установить', icon: Icons.install_mobile, onPressed: () => d.install(buildId)),
          const SizedBox(height: 8),
          save,
        ]),
      InstallPhase.needsPermission => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoticeBox(
            text: job.installMessage ?? 'Нужно разрешение на установку приложений.',
            color: AppColors.warning,
            icon: Icons.shield_outlined,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => d.install(buildId),
            icon: const Icon(Icons.settings),
            label: const Text('Открыть настройки'),
          ),
        ]),
      InstallPhase.preparing => _progress(
          context,
          'Подготовка установки',
          job.installProgress,
          job.installProgress == null ? '' : '${((job.installProgress ?? 0) * 100).floor()}%',
        ),
      InstallPhase.confirm => _progress(context, 'Подтвердите установку в системном окне', null, ''),
      InstallPhase.installing => _progress(context, 'Установка…', null, ''),
      InstallPhase.installed => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const SuccessCheck(size: 36),
            const SizedBox(width: 12),
            Expanded(child: Text('Приложение установлено', style: theme.textTheme.titleSmall)),
          ]),
          const SizedBox(height: 12),
          if (job.packageName != null)
            GradientButton(
              label: 'Открыть приложение',
              icon: Icons.open_in_new,
              height: compact ? 48 : 56,
              onPressed: () async {
                final ok = await d.launch(buildId);
                if (!ok && context.mounted) showSnack(context, 'У приложения нет значка запуска в лаунчере.');
              },
            ),
          const SizedBox(height: 8),
          save,
        ]),
      InstallPhase.failed => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoticeBox(
            text: job.installMessage ?? 'Установка не удалась.',
            color: theme.colorScheme.error,
            icon: Icons.error_outline,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => d.install(buildId),
            icon: const Icon(Icons.refresh),
            label: const Text('Повторить установку'),
          ),
          const SizedBox(height: 8),
          save,
        ]),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: 14), body]);
  }

  Widget _progress(BuildContext context, String title, double? value, String trailing) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
        Text(trailing, style: theme.textTheme.titleSmall),
      ]),
      const SizedBox(height: 10),
      GradientProgressBar(value: value),
    ]);
  }

  static String _short(Duration d) => d.inSeconds < 60 ? '${d.inSeconds} с' : '${d.inMinutes} мин ${d.inSeconds % 60} с';
}
