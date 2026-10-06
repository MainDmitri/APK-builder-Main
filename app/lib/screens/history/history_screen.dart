import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend/build_backend.dart';
import '../../theme/app_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/section_card.dart';
import '../builder/apk_panel.dart';

/// Builds known to the current backend (engine history / GitHub releases)
/// with download and install of each APK.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Future<List<RemoteBuildSummary>>? _future;
  BuildBackend? _backend;
  String? _expandedId;

  void _load(BuildBackend backend) {
    _backend = backend;
    _future = backend.history();
  }

  @override
  Widget build(BuildContext context) {
    final backend = context.watch<BuildBackend?>();
    if (backend == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('История сборок')),
        body: Center(
          child: FilledButton(onPressed: widget.onOpenSettings, child: const Text('Настроить сборщик')),
        ),
      );
    }
    if (!identical(backend, _backend)) _load(backend);
    return Scaffold(
      appBar: AppBar(
        title: const Text('История сборок'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Обновить', onPressed: () => setState(() => _load(backend))),
        ],
      ),
      body: FutureBuilder<List<RemoteBuildSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: SizedBox(width: 160, child: GradientProgressBar(value: null, height: 6)));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: MessageList(messages: ['${snapshot.error}'], error: true),
              ),
            );
          }
          final builds = snapshot.data ?? const [];
          if (builds.isEmpty) return const Center(child: Text('Сборок пока нет'));
          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _load(backend));
              await _future;
            },
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: builds.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => FadeSlideIn(
                    delay: Duration(milliseconds: 40 * i.clamp(0, 10)),
                    child: _BuildCard(
                      summary: builds[i],
                      backend: backend,
                      expanded: _expandedId == builds[i].id,
                      onToggle: () => setState(() => _expandedId = _expandedId == builds[i].id ? null : builds[i].id),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BuildCard extends StatelessWidget {
  const _BuildCard({required this.summary, required this.backend, required this.expanded, required this.onToggle});

  final RemoteBuildSummary summary;
  final BuildBackend backend;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = summary.state == RemoteBuildState.succeeded;
    final (IconData icon, Color color) = switch (summary.state) {
      RemoteBuildState.succeeded => (Icons.check_circle_rounded, AppColors.success),
      RemoteBuildState.failed => (Icons.error_rounded, theme.colorScheme.error),
      _ => (Icons.hourglass_top_rounded, AppColors.warning),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          onTap: ok ? onToggle : null,
          leading: Icon(icon, color: color, size: 30),
          title: Text(summary.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${MaterialLocalizations.of(context).formatShortDate(summary.createdAt)} '
              '${TimeOfDay.fromDateTime(summary.createdAt).format(context)} · ${summary.apkFileName ?? summary.id}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (summary.detailsUrl != null)
              IconButton(
                tooltip: 'Открыть в GitHub',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => launchUrl(Uri.parse(summary.detailsUrl!), mode: LaunchMode.externalApplication),
              ),
            if (ok)
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: const Icon(Icons.expand_more),
              ),
          ]),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: ok && expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ApkPanel(backend: backend, buildId: summary.id, compact: true),
                )
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}
