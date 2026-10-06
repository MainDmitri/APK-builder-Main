import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend/build_backend.dart';
import '../../state/build_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/section_card.dart';
import 'apk_panel.dart';

/// Progress, stages, log and result of the running / finished build.
class BuildProgressSection extends StatelessWidget {
  const BuildProgressSection({super.key, required this.backend});

  final BuildBackend? backend;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BuildController>();
    final status = c.status;
    final theme = Theme.of(context);
    final error = c.buildError ?? status?.error;

    final (IconData icon, String title) = switch (status?.state) {
      _ when c.buildError != null => (Icons.error_outline, 'Не удалось отправить сборку'),
      null => (Icons.cloud_upload_outlined, 'Проект отправлен'),
      RemoteBuildState.queued => (
          Icons.hourglass_top,
          status!.queuePosition == null ? (status.stageTitle ?? 'В очереди') : 'В очереди, позиция ${status.queuePosition}',
        ),
      RemoteBuildState.running => (Icons.precision_manufacturing_outlined, status!.stageTitle ?? 'Сборка…'),
      RemoteBuildState.succeeded => (Icons.verified_outlined, 'APK готов'),
      RemoteBuildState.failed => (Icons.error_outline, 'Ошибка сборки'),
    };
    final progress = c.stageProgress;

    return SectionCard(
      title: title,
      icon: icon,
      trailing: c.startedAt == null ? null : _Elapsed(start: c.startedAt!, end: c.finishedAt),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.buildRunning || c.submitting) ...[
            Row(children: [
              Expanded(
                child: Text(
                  progress == null ? 'Сборка идёт на сервере — статус обновляется автоматически' : 'Этап ${status!.currentStage! + 1} из ${status.stages.length}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              if (progress != null) Text('${(progress * 100).round()}%', style: theme.textTheme.titleSmall),
            ]),
            const SizedBox(height: 10),
            GradientProgressBar(value: progress),
            const SizedBox(height: 4),
          ],
          if (status?.state == RemoteBuildState.succeeded) ...[
            Row(children: [
              const SuccessCheck(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(status!.apkFileName ?? 'app.apk', style: theme.textTheme.titleMedium),
                  Text(
                    [
                      if (status.apkSize != null) formatBytes(status.apkSize!),
                      if (status.signingSchemes.isNotEmpty) 'подпись ${status.signingSchemes.join(' + ')}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            if (backend != null && c.buildId != null) ApkPanel(backend: backend!, buildId: c.buildId!),
            if (status.apkSha256 != null) ...[
              const SizedBox(height: 12),
              SelectableText('SHA-256: ${status.apkSha256}',
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
          if (status != null && status.stages.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final (i, stage) in status.stages.indexed) _StageRow(title: stage, state: _stageState(status, i)),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            NoticeBox(text: error, color: theme.colorScheme.error, icon: Icons.error_outline),
          ],
          if (status != null && status.warnings.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Предупреждения анализа (${status.warnings.length})'),
              children: [MessageList(messages: status.warnings, error: false)],
            ),
          if (status?.detailsUrl != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(status!.detailsUrl!), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Открыть в GitHub'),
              ),
            ),
          const SizedBox(height: 8),
          _LogView(lines: c.log, initiallyExpanded: status?.state != RemoteBuildState.succeeded),
        ],
      ),
    );
  }

  static _Stage _stageState(RemoteBuildStatus status, int index) {
    if (status.state == RemoteBuildState.succeeded) return _Stage.done;
    final current = status.currentStage;
    if (current == null) return _Stage.pending;
    if (index < current) return _Stage.done;
    if (index > current) return _Stage.pending;
    return status.state == RemoteBuildState.failed ? _Stage.failed : _Stage.running;
  }
}

/// Build duration, ticking while the build runs.
class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.start, required this.end});

  final DateTime start;
  final DateTime? end;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Elapsed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.end == null) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_outlined, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          formatDuration((widget.end ?? DateTime.now()).difference(widget.start)),
          style: TextStyle(fontFeatures: const [FontFeature.tabularFigures()], color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      ]),
    );
  }
}

enum _Stage { pending, running, done, failed }

class _StageRow extends StatelessWidget {
  const _StageRow({required this.title, required this.state});

  final String title;
  final _Stage state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget leading = switch (state) {
      _Stage.pending => Icon(Icons.radio_button_unchecked, key: const ValueKey('p'), size: 20, color: scheme.outline),
      _Stage.running => const SizedBox.square(
          key: ValueKey('r'),
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.cyan),
        ),
      _Stage.done => const Icon(Icons.check_circle_rounded, key: ValueKey('d'), size: 20, color: AppColors.success),
      _Stage.failed => Icon(Icons.cancel_rounded, key: const ValueKey('f'), size: 20, color: scheme.error),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
          child: leading,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontWeight: state == _Stage.running ? FontWeight.w700 : FontWeight.w400,
                  color: state == _Stage.pending ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
            child: Text(title),
          ),
        ),
      ]),
    );
  }
}

class _LogView extends StatefulWidget {
  const _LogView({required this.lines, required this.initiallyExpanded});

  final List<String> lines;
  final bool initiallyExpanded;

  @override
  State<_LogView> createState() => _LogViewState();
}

class _LogViewState extends State<_LogView> {
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void didUpdateWidget(covariant _LogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != _lastCount) {
      _lastCount = widget.lines.length;
      final atBottom = !_scroll.hasClients || _scroll.position.pixels >= _scroll.position.maxScrollExtent - 48;
      if (atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: widget.initiallyExpanded,
      title: Text('Журнал сборки (${widget.lines.length})', style: Theme.of(context).textTheme.labelLarge),
      trailing: IconButton(
        tooltip: 'Скопировать журнал',
        icon: const Icon(Icons.copy_all),
        onPressed: widget.lines.isEmpty
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: widget.lines.join('\n')));
                showSnack(context, 'Журнал скопирован');
              },
      ),
      children: [
        Container(
          height: 300,
          decoration: BoxDecoration(
            color: const Color(0xFF050507),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(10),
          child: widget.lines.isEmpty
              ? const Center(child: Text('Журнал появится после запуска', style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  controller: _scroll,
                  itemCount: widget.lines.length,
                  itemBuilder: (_, i) => Text(
                    widget.lines[i],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Color(0xFFC9D1D9)),
                  ),
                ),
        ),
      ],
    );
  }
}
