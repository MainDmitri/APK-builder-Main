import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/apk_installer.dart';
import '../../services/backend/build_backend.dart';
import '../../services/file_service.dart';
import '../../widgets/section_card.dart';

/// Builds known to the current backend (engine history / GitHub releases).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Future<List<RemoteBuildSummary>>? _future;
  BuildBackend? _backend;
  String? _busyId;

  void _load(BuildBackend backend) {
    _backend = backend;
    _future = backend.history();
  }

  Future<void> _download(RemoteBuildSummary build, {required bool install}) async {
    final backend = _backend;
    if (backend == null) return;
    setState(() => _busyId = build.id);
    try {
      final apk = await backend.downloadApk(build.id);
      String? message;
      if (install) {
        message = await const ApkInstaller().install(apk.bytes, apk.fileName);
      } else {
        final saved = await const FileService().save(apk.fileName, apk.bytes, mimeType: 'application/vnd.android.package-archive');
        message = saved == null ? 'Сохранение отменено' : 'APK сохранён: $saved';
      }
      if (message != null && mounted) showSnack(context, message);
    } on BackendException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
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
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
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
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: builds.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final b = builds[i];
                final ok = b.state == RemoteBuildState.succeeded;
                return ListTile(
                  leading: Icon(
                    switch (b.state) {
                      RemoteBuildState.succeeded => Icons.check_circle,
                      RemoteBuildState.failed => Icons.error,
                      _ => Icons.hourglass_top,
                    },
                    color: ok ? Colors.green : (b.state == RemoteBuildState.failed ? Theme.of(context).colorScheme.error : null),
                  ),
                  title: Text(b.title),
                  subtitle: Text('${MaterialLocalizations.of(context).formatShortDate(b.createdAt)} '
                      '${TimeOfDay.fromDateTime(b.createdAt).format(context)} · ${b.apkFileName ?? b.id}'),
                  trailing: _busyId == b.id
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          if (b.detailsUrl != null)
                            IconButton(
                              tooltip: 'Открыть в GitHub',
                              icon: const Icon(Icons.open_in_new),
                              onPressed: () => launchUrl(Uri.parse(b.detailsUrl!), mode: LaunchMode.externalApplication),
                            ),
                          if (ok && const ApkInstaller().isSupported)
                            IconButton(
                              tooltip: 'Установить',
                              icon: const Icon(Icons.install_mobile),
                              onPressed: () => _download(b, install: true),
                            ),
                          if (ok)
                            IconButton(
                              tooltip: 'Сохранить APK',
                              icon: const Icon(Icons.download),
                              onPressed: () => _download(b, install: false),
                            ),
                        ]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
