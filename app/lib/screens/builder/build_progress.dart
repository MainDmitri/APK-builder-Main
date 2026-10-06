import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend/build_backend.dart';
import '../../state/build_controller.dart';
import '../../widgets/section_card.dart';

/// Stages, log and result of the running / finished build.
class BuildProgressSection extends StatelessWidget {
  const BuildProgressSection({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BuildController>();
    final status = c.status;
    final scheme = Theme.of(context).colorScheme;
    final error = c.buildError ?? status?.error;

    final (IconData icon, String title) = switch (status?.state) {
      _ when c.buildError != null => (Icons.error, 'Не удалось отправить сборку'),
      null => (Icons.cloud_upload, 'Сборка отправлена, ожидание статуса…'),
      RemoteBuildState.queued => (
          Icons.hourglass_top,
          status!.queuePosition == null ? (status.stageTitle ?? 'В очереди') : 'В очереди, позиция ${status.queuePosition}',
        ),
      RemoteBuildState.running => (Icons.autorenew, status!.stageTitle ?? 'Сборка…'),
      RemoteBuildState.succeeded => (Icons.check_circle, 'APK готов'),
      RemoteBuildState.failed => (Icons.error, 'Ошибка сборки'),
    };

    return SectionCard(
      title: title,
      icon: icon,
      trailing: c.buildId == null ? null : Text(c.buildId!, style: Theme.of(context).textTheme.labelSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.buildRunning) const LinearProgressIndicator(),
          if (status != null && status.stages.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final (i, stage) in status.stages.indexed) _StageRow(title: stage, state: _stageState(status, i)),
          ],
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(error, style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],
          if (status != null && status.warnings.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Предупреждения анализа (${status.warnings.length})'),
              children: [MessageList(messages: status.warnings, error: false)],
            ),
          if (status?.state == RemoteBuildState.succeeded) _Result(status: status!),
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
          _LogView(lines: c.log),
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

enum _Stage { pending, running, done, failed }

class _StageRow extends StatelessWidget {
  const _StageRow({required this.title, required this.state});

  final String title;
  final _Stage state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget leading = switch (state) {
      _Stage.pending => Icon(Icons.radio_button_unchecked, size: 20, color: scheme.outline),
      _Stage.running => const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      _Stage.done => const Icon(Icons.check_circle, size: 20, color: Colors.green),
      _Stage.failed => Icon(Icons.cancel, size: 20, color: scheme.error),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontWeight: state == _Stage.running ? FontWeight.w600 : null,
              color: state == _Stage.pending ? scheme.outline : null,
            ),
          ),
        ),
      ]),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.status});

  final RemoteBuildStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BuildController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.android, color: Colors.green, size: 36),
          title: Text(status.apkFileName ?? 'app.apk'),
          subtitle: Text([
            if (status.apkSize != null) formatBytes(status.apkSize!),
            if (status.signingSchemes.isNotEmpty) 'подпись ${status.signingSchemes.join(' + ')}',
          ].join(' · ')),
        ),
        if (status.apkSha256 != null)
          SelectableText('SHA-256: ${status.apkSha256}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (c.installer.isSupported)
            FilledButton.icon(
              onPressed: c.downloading
                  ? null
                  : () async {
                      final error = await c.installApk();
                      if (error != null && context.mounted) showSnack(context, error);
                    },
              icon: const Icon(Icons.install_mobile),
              label: const Text('Установить'),
            ),
          OutlinedButton.icon(
            onPressed: c.downloading
                ? null
                : () async {
                    final message = await c.saveApk();
                    if (context.mounted) showSnack(context, message);
                  },
            icon: c.downloading
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: const Text('Сохранить APK'),
          ),
        ]),
      ],
    );
  }
}

class _LogView extends StatefulWidget {
  const _LogView({required this.lines});

  final List<String> lines;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text('Лог сборки (${widget.lines.length})', style: Theme.of(context).textTheme.labelLarge),
          const Spacer(),
          IconButton(
            tooltip: 'Скопировать лог',
            icon: const Icon(Icons.copy_all),
            onPressed: widget.lines.isEmpty
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: widget.lines.join('\n')));
                    showSnack(context, 'Лог скопирован');
                  },
          ),
        ]),
        Container(
          height: 320,
          decoration: BoxDecoration(color: const Color(0xFF111418), borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(8),
          child: widget.lines.isEmpty
              ? const Center(child: Text('Лог появится после запуска', style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  controller: _scroll,
                  itemCount: widget.lines.length,
                  itemBuilder: (_, i) => Text(
                    widget.lines[i],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFD7DCE2)),
                  ),
                ),
        ),
      ],
    );
  }
}
