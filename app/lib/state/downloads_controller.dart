import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../services/backend/build_backend.dart';
import '../services/file_service.dart';
import '../services/transfer/apk_store.dart';
import '../services/transfer/transfer_models.dart';

/// Download (and, for an APK, installation) state of one file of a build.
class ApkJob {
  ApkJob(this.buildId, this.kind);

  final String buildId;
  final ArtifactKind kind;
  String? fileName;
  TransferPhase phase = TransferPhase.queued;
  int received = 0;
  int? total;

  /// Smoothed download speed, bytes per second.
  double speed = 0;
  String? message;
  String? path;

  InstallPhase? install;
  double? installProgress;
  String? installMessage;
  String? packageName;

  DateTime? _sampleAt;
  int _sampleBytes = 0;

  double? get fraction {
    final t = total;
    if (phase == TransferPhase.done) return 1;
    if (t == null || t <= 0) return null;
    return (received / t).clamp(0.0, 1.0);
  }

  Duration? get remaining {
    final t = total;
    if (t == null || speed < 1 || phase != TransferPhase.downloading) return null;
    return Duration(milliseconds: ((t - received) / speed * 1000).round());
  }

  bool get downloaded => phase == TransferPhase.done;

  bool get active => phase == TransferPhase.queued || phase == TransferPhase.downloading || phase == TransferPhase.paused;

  bool get installing =>
      install == InstallPhase.preparing || install == InstallPhase.confirm || install == InstallPhase.installing;

  void _apply(TransferUpdate u) {
    final now = DateTime.now();
    final at = _sampleAt;
    if (u.phase == TransferPhase.downloading && at != null) {
      final seconds = now.difference(at).inMicroseconds / 1e6;
      if (seconds >= 0.25) {
        final instant = (u.received - _sampleBytes) / seconds;
        speed = speed == 0 ? instant : speed * 0.6 + instant * 0.4;
        _sampleAt = now;
        _sampleBytes = u.received;
      }
    } else {
      _sampleAt = now;
      _sampleBytes = u.received;
    }
    phase = u.phase;
    received = u.received;
    total = u.total ?? total;
    message = u.message;
    if (u.path != null) path = u.path;
    if (u.phase != TransferPhase.downloading) speed = u.phase == TransferPhase.done ? speed : 0;
  }
}

/// APK / IPA downloads and APK installs of all builds (current build and history).
class DownloadsController extends ChangeNotifier with WidgetsBindingObserver {
  DownloadsController({ApkStore? store, this.files = const FileService()}) : store = store ?? ApkStore() {
    WidgetsBinding.instance.addObserver(this);
  }

  final ApkStore store;
  final FileService files;
  final Map<String, ApkJob> _jobs = {};
  final Map<String, StreamSubscription<TransferUpdate>> _downloads = {};
  final Map<String, StreamSubscription<InstallUpdate>> _installs = {};
  final Set<String> _installWhenReady = {};

  bool get canInstall => store.canInstall;

  /// Downloads of the APK use the build id as key, IPAs `<id>.ipa`.
  static String _key(String buildId, ArtifactKind kind) => kind == ArtifactKind.apk ? buildId : '$buildId.${kind.name}';

  ApkJob? job(String buildId, {ArtifactKind kind = ArtifactKind.apk}) => _jobs[_key(buildId, kind)];

  /// Starts (or resumes) the download of a successful build's APK or IPA.
  /// With [thenInstall] the APK installer opens as soon as the file is ready.
  Future<void> download(
    BuildBackend backend,
    String buildId, {
    bool thenInstall = false,
    ArtifactKind kind = ArtifactKind.apk,
  }) async {
    final key = _key(buildId, kind);
    final install = thenInstall && kind == ArtifactKind.apk;
    if (install) _installWhenReady.add(key);
    final existing = _jobs[key];
    if (existing != null && (existing.active || existing.downloaded)) {
      if (existing.downloaded && install) await this.install(buildId);
      return;
    }
    final job = _jobs[key] = ApkJob(buildId, kind);
    notifyListeners();
    final ArtifactSource source;
    try {
      source = await backend.artifactSource(buildId, kind);
    } on BackendException catch (e) {
      job
        ..phase = TransferPhase.failed
        ..message = e.message;
      _installWhenReady.remove(key);
      notifyListeners();
      return;
    }
    job
      ..fileName = source.fileName
      ..total = source.size;
    notifyListeners();
    _downloads[key] = store.download(source, key).listen(
      (update) {
        job._apply(update);
        notifyListeners();
        if (update.phase == TransferPhase.done && _installWhenReady.remove(key)) unawaited(this.install(buildId));
        if (update.phase == TransferPhase.failed) _installWhenReady.remove(key);
      },
      onError: (Object e) {
        job
          ..phase = TransferPhase.failed
          ..message = '$e';
        _installWhenReady.remove(key);
        notifyListeners();
      },
      onDone: () => _downloads.remove(key),
    );
  }

  Future<void> cancel(String buildId, {ArtifactKind kind = ArtifactKind.apk}) async {
    final key = _key(buildId, kind);
    _installWhenReady.remove(key);
    await _downloads.remove(key)?.cancel();
    await store.cancel(key);
    _jobs.remove(key);
    notifyListeners();
  }

  /// Opens the system installer for a downloaded APK and tracks its progress.
  Future<void> install(String buildId) async {
    final job = _jobs[buildId];
    final path = job?.path;
    if (job == null || path == null || job.installing) return;
    if (!await store.installAllowed()) {
      job
        ..install = InstallPhase.needsPermission
        ..installMessage = 'Разрешите AppBuilder устанавливать приложения — установка продолжится автоматически.';
      notifyListeners();
      await store.openInstallSettings();
      return;
    }
    job
      ..install = InstallPhase.preparing
      ..installProgress = 0
      ..installMessage = null;
    notifyListeners();
    await _installs.remove(buildId)?.cancel();
    _installs[buildId] = store.install(path).listen(
      (u) {
        job
          ..install = u.phase
          ..installProgress = u.progress ?? job.installProgress
          ..installMessage = u.message;
        if (u.packageName != null) job.packageName = u.packageName;
        notifyListeners();
      },
      onDone: () => _installs.remove(buildId),
    );
  }

  /// Saves the APK / IPA through the system "save as" dialog.
  Future<String> save(String buildId, {ArtifactKind kind = ArtifactKind.apk}) async {
    final key = _key(buildId, kind);
    final job = _jobs[key];
    if (job == null || !job.downloaded) return '${kind.label} ещё не скачан.';
    final Uint8List bytes = await store.read(key, job.path);
    final location = await files.save(job.fileName ?? 'app.${kind.name}', bytes, mimeType: kind.mimeType);
    return location == null ? 'Сохранение отменено' : '${kind.label} сохранён: $location';
  }

  /// Launches the installed app. Returns false if Android has no launcher entry.
  Future<bool> launch(String buildId) async {
    final packageName = _jobs[buildId]?.packageName;
    return packageName != null && await store.launch(packageName);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    for (final job in _jobs.values) {
      // Back from "Install unknown apps": continue automatically.
      if (job.install == InstallPhase.needsPermission) {
        unawaited(store.installAllowed().then((allowed) {
          if (allowed && job.install == InstallPhase.needsPermission) {
            job.install = null;
            return install(job.buildId);
          }
        }));
      }
      // Back from the system confirmation: Android is installing now.
      if (job.install == InstallPhase.confirm) {
        job.install = InstallPhase.installing;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in [..._downloads.values, ..._installs.values]) {
      s.cancel();
    }
    super.dispose();
  }
}
