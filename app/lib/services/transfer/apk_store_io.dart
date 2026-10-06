import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../backend/build_backend.dart';
import 'install_messages.dart';
import 'native_bridge.dart';
import 'transfer_models.dart';

/// Downloads and installs APKs.
///
/// Android: the system DownloadManager (continues in the background, resumes
/// after network loss, progress notification) and PackageInstaller sessions.
/// Desktop: streamed HTTP download into the application data folder.
/// Finished files are kept per build, so a repeated install is instant.
class ApkStore {
  ApkStore({
    this.bridge = const NativeBridge(),
    http.Client? client,
    this.storageDir = getApplicationSupportDirectory,
  }) : _client = client ?? http.Client();

  final NativeBridge bridge;
  final http.Client _client;

  /// Desktop: folder that keeps downloaded APKs.
  final Future<Directory> Function() storageDir;
  final Map<String, int> _systemDownloads = {};

  /// Downloaded APKs of this many recent builds are kept.
  static const keepBuilds = 8;
  static const _pollInterval = Duration(milliseconds: 350);

  bool get canInstall => bridge.available;

  Stream<TransferUpdate> download(ApkSource source, String buildId) =>
      bridge.available ? _downloadSystem(source, buildId) : _downloadHttp(source, buildId);

  Future<void> cancel(String buildId) async {
    final id = _systemDownloads.remove(buildId);
    if (id != null) await bridge.cancelDownload(id);
  }

  Future<Uint8List> read(String buildId, String? path) => File(path!).readAsBytes();

  Future<bool> installAllowed() => bridge.canInstall();

  Future<void> openInstallSettings() => bridge.openInstallSettings();

  Future<bool> launch(String packageName) => bridge.launch(packageName);

  static String _safeName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');

  static bool _isComplete(File file, int? size) => size != null && file.existsSync() && file.lengthSync() == size;

  /// Removes downloads of old builds, keeping [keepBuilds] most recent ones.
  static void _prune(Directory root, String current) {
    if (!root.existsSync()) return;
    final dirs = root.listSync().whereType<Directory>().where((d) => !d.path.endsWith('/$current')).toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final old in dirs.skip(keepBuilds - 1)) {
      try {
        old.deleteSync(recursive: true);
      } on FileSystemException {
        // A file still open elsewhere: retried on the next download.
      }
    }
  }

  Stream<TransferUpdate> _downloadSystem(ApkSource source, String buildId) async* {
    final root = await bridge.downloadsDir();
    final relative = 'apk/$buildId/${_safeName(source.fileName)}';
    final file = File('$root/$relative');
    _prune(Directory('$root/apk'), buildId);
    if (_isComplete(file, source.size) && !_systemDownloads.containsKey(buildId)) {
      yield TransferUpdate(TransferPhase.done, received: source.size!, total: source.size, path: file.path);
      return;
    }
    yield TransferUpdate(TransferPhase.queued, total: source.size);
    final id = await bridge.enqueueDownload(
      url: source.url,
      headers: source.headers,
      relativePath: relative,
      title: source.fileName,
      tag: 'AppBuilder · сборка $buildId',
    );
    _systemDownloads[buildId] = id;
    try {
      await for (final _ in Stream<void>.periodic(_pollInterval)) {
        final q = await bridge.queryDownload(id);
        final received = (q['downloaded'] as num?)?.toInt() ?? 0;
        final reported = (q['total'] as num?)?.toInt() ?? -1;
        final total = reported > 0 ? reported : source.size;
        final reason = (q['reason'] as num?)?.toInt() ?? 0;
        switch (q['status']) {
          case 'successful':
            yield TransferUpdate(TransferPhase.done, received: total ?? received, total: total, path: file.path);
            return;
          case 'failed':
            yield TransferUpdate(TransferPhase.failed, received: received, total: total,
                message: TransferMessages.downloadFailure(reason));
            return;
          case 'missing':
            yield const TransferUpdate(TransferPhase.failed, message: 'Загрузка отменена.');
            return;
          case 'paused':
            yield TransferUpdate(TransferPhase.paused, received: received, total: total,
                message: TransferMessages.downloadPause(reason));
          case 'pending':
            yield TransferUpdate(TransferPhase.queued, received: received, total: total);
          default:
            yield TransferUpdate(TransferPhase.downloading, received: received, total: total);
        }
      }
    } finally {
      if (_systemDownloads[buildId] == id) _systemDownloads.remove(buildId);
    }
  }

  Stream<TransferUpdate> _downloadHttp(ApkSource source, String buildId) async* {
    final root = Directory('${(await storageDir()).path}/apk');
    _prune(root, buildId);
    final file = File('${root.path}/$buildId/${_safeName(source.fileName)}');
    if (_isComplete(file, source.size)) {
      yield TransferUpdate(TransferPhase.done, received: source.size!, total: source.size, path: file.path);
      return;
    }
    file.parent.createSync(recursive: true);
    yield TransferUpdate(TransferPhase.queued, total: source.size);

    final http.StreamedResponse response;
    try {
      response = await _client
          .send(http.Request('GET', source.url)..headers.addAll(source.headers))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      yield const TransferUpdate(TransferPhase.failed, message: 'Сервер не отвечает.');
      return;
    } on http.ClientException catch (e) {
      yield TransferUpdate(TransferPhase.failed, message: 'Нет соединения: ${e.message}');
      return;
    }
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      yield TransferUpdate(TransferPhase.failed, message: TransferMessages.downloadFailure(response.statusCode));
      return;
    }

    final total = response.contentLength ?? source.size;
    final part = File('${file.path}.part');
    final sink = part.openWrite();
    var received = 0;
    var complete = false;
    var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastReport) >= const Duration(milliseconds: 120)) {
          lastReport = now;
          yield TransferUpdate(TransferPhase.downloading, received: received, total: total);
        }
      }
      complete = true;
    } on Exception catch (e) {
      yield TransferUpdate(TransferPhase.failed, received: received, total: total, message: 'Связь прервалась: $e');
    } finally {
      await sink.close();
      if (!complete && part.existsSync()) part.deleteSync();
    }
    if (!complete) return;
    final expected = source.size ?? total;
    if (expected != null && received != expected) {
      part.deleteSync();
      yield TransferUpdate(TransferPhase.failed, received: received, total: total, message: 'Файл скачан не полностью.');
      return;
    }
    part.renameSync(file.path);
    yield TransferUpdate(TransferPhase.done, received: received, total: received, path: file.path);
  }

  /// Installs a downloaded APK through a PackageInstaller session (Android).
  Stream<InstallUpdate> install(String path) {
    final controller = StreamController<InstallUpdate>();
    StreamSubscription<Map<Object?, Object?>>? events;
    int? session;
    final early = <Map<Object?, Object?>>[];
    var last = InstallPhase.preparing;

    void emit(InstallUpdate update) {
      if (controller.isClosed) return;
      last = update.phase;
      controller.add(update);
      if (update.phase == InstallPhase.installed || update.phase == InstallPhase.failed) {
        events?.cancel();
        controller.close();
      }
    }

    void handle(Map<Object?, Object?> e) {
      if (e['sessionId'] != session) return;
      switch (e['stage']) {
        case 'staging':
          emit(InstallUpdate(InstallPhase.preparing, progress: (e['progress'] as num?)?.toDouble()));
        case 'committed':
          // The confirmation may already be on screen: keep that state.
          if (last != InstallPhase.confirm) emit(const InstallUpdate(InstallPhase.installing));
        case 'confirm':
          emit(const InstallUpdate(InstallPhase.confirm));
        case 'success':
          emit(InstallUpdate(InstallPhase.installed, packageName: e['packageName'] as String?));
        case 'failure':
          emit(InstallUpdate(
            InstallPhase.failed,
            message: TransferMessages.installFailure((e['code'] as num?)?.toInt(), e['message'] as String?),
          ));
      }
    }

    controller
      ..onListen = () async {
        events = bridge.installEvents.listen((e) => session == null ? early.add(e) : handle(e));
        emit(const InstallUpdate(InstallPhase.preparing, progress: 0));
        try {
          session = await bridge.install(path);
          for (final e in early) {
            handle(e);
          }
          early.clear();
        } on NativeException catch (e) {
          emit(InstallUpdate(InstallPhase.failed, message: e.message));
        }
      }
      ..onCancel = () => events?.cancel();
    return controller.stream;
  }
}
