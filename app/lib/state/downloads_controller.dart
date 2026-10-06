import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../services/backend/build_backend.dart';
import '../services/file_service.dart';
import '../services/transfer/apk_store.dart';
import '../services/transfer/transfer_models.dart';

/// Download and installation state of the APK of one build.
class ApkJob {
  ApkJob(this.buildId);

  final String buildId;
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

/// APK downloads and installs of all builds (current build and history).
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

  ApkJob? job(String buildId) => _jobs[buildId];

  /// Starts (or resumes) the download of a successful build's APK.
  /// With [thenInstall] the installer opens as soon as the file is ready.
  Future<void> download(BuildBackend backend, String buildId, {bool thenInstall = false}) async {
    if (thenInstall) _installWhenReady.add(buildId);
    final existing = _jobs[buildId];
    if (existing != null && (existing.active || existing.downloaded)) {
      if (existing.downloaded && thenInstall) await install(buildId);
      return;
    }
    final job = _jobs[buildId] = ApkJob(buildId);
    notifyListeners();
    final ApkSource source;
    try {
      source = await backend.apkSource(buildId);
    } on BackendException catch (e) {
      job
        ..phase = TransferPhase.failed
        ..message = e.message;
      _installWhenReady.remove(buildId);
      notifyListeners();
      return;
    }
    job
      ..fileName = source.fileName
      ..total = source.size;
    notifyListeners();
    _downloads[buildId] = store.download(source, buildId).listen(
      (update) {
        job._apply(update);
        notifyListeners();
        if (update.phase == TransferPhase.done && _installWhenReady.remove(buildId)) unawaited(install(buildId));
        if (update.phase == TransferPhase.failed) _installWhenReady.remove(buildId);
      },
      onError: (Object e) {
        job
          ..phase = TransferPhase.failed
          ..message = '$e';
        _installWhenReady.remove(buildId);
        notifyListeners();
      },
      onDone: () => _downloads.remove(buildId),
    );
  }

  Future<void> cancel(String buildId) async {
    _installWhenReady.remove(buildId);
    await _downloads.remove(buildId)?.cancel();
    await store.cancel(buildId);
    _jobs.remove(buildId);
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

  /// Saves the APK through the system "save as" dialog.
  Future<String> save(String buildId) async {
    final job = _jobs[buildId];
    if (job == null || !job.downloaded) return 'APK ещё не скачан.';
    final Uint8List bytes = await store.read(buildId, job.path);
    final location = await files.save(job.fileName ?? 'app.apk', bytes, mimeType: 'application/vnd.android.package-archive');
    return location == null ? 'Сохранение отменено' : 'APK сохранён: $location';
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
