import 'dart:async';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/backend/build_backend.dart';
import '../services/file_service.dart';
import '../services/transfer/native_bridge.dart';
import 'downloads_controller.dart';

/// Result of reading a picked ZIP in a background isolate.
typedef _ZipInfo = ({ProjectAnalysis analysis, ProjectIcon? icon, Uint8List? iconBytes});

_ZipInfo _readZip(Uint8List bytes) {
  final source = ZipMemorySource.fromBytes(bytes);
  final analysis = const ProjectAnalyzer().analyze(source);
  final icon = ProjectAnalyzer.findProjectIcon(analysis, source);
  return (
    analysis: analysis,
    icon: icon,
    iconBytes: icon != null && icon.isRaster ? source.readBytes(icon.path) : null,
  );
}

/// State of the "Build" screen: project, parameters, icon, signing and the
/// running remote build.
class BuildController extends ChangeNotifier {
  BuildController({this.files = const FileService(), this.downloads, this.bridge = const NativeBridge()});

  final FileService files;

  /// Downloads the APK as soon as the build succeeds (null in unit tests).
  final DownloadsController? downloads;
  final NativeBridge bridge;

  // ---------------------------------------------------------------- project
  PickedFile? project;
  ProjectAnalysis? analysis;
  String? projectError;
  bool analyzing = false;

  /// Icon the project provides itself (null → letter icon).
  ProjectIcon? projectIcon;
  Uint8List? projectIconBytes;

  // -------------------------------------------------------------- parameters
  final appName = TextEditingController();
  final packageName = TextEditingController();
  final versionName = TextEditingController(text: '1.0.0');
  final versionCode = TextEditingController(text: '1');
  ScreenOrientation orientation = ScreenOrientation.sensor;
  Set<AppPermission> permissions = {AppPermission.internet};
  String themeColor = '#1565C0';

  // ------------------------------------------------------------------- icon
  /// Picture chosen in the app; replaces the project's icon.
  PickedFile? icon;
  String? iconError;

  static const maxIconBytes = 5 * 1024 * 1024;

  // ---------------------------------------------------------------- signing
  SigningMode signing = SigningMode.debug;
  PickedFile? keystore;
  String? keystoreFormatError;
  final storePassword = TextEditingController();
  final keyAlias = TextEditingController();
  final keyPassword = TextEditingController();
  KeystoreValidation? keystoreCheck;
  bool checkingKeystore = false;

  // ------------------------------------------------------------------ build
  BuildBackend? _backend;
  String? buildId;
  RemoteBuildStatus? status;
  final List<String> log = [];
  int _logIndex = 0;
  String? buildError;
  bool submitting = false;
  DateTime? startedAt;
  DateTime? finishedAt;
  Timer? _poll;
  bool _polling = false;

  bool get isNativeGradle => analysis?.kind == ProjectKind.nativeGradle;
  bool get isWeb => analysis?.kind.isWeb ?? false;
  bool get buildRunning => buildId != null && !(status?.isFinished ?? false) && buildError == null;

  /// Gradle projects keep their own launcher icon.
  bool get iconSupported => analysis != null && analysis!.canBuild && !isNativeGradle;

  /// 0..1 by pipeline stages, or null when the backend reports no stages.
  double? get stageProgress {
    final s = status;
    if (s == null) return null;
    if (s.state == RemoteBuildState.succeeded) return 1;
    if (s.stages.isEmpty || s.currentStage == null) return null;
    return (s.currentStage! + 0.5) / s.stages.length;
  }

  /// Problems that block the "Build" button.
  List<String> readinessErrors(BuildBackend? backend) => [
        if (backend == null) 'Настройте сервер сборки или GitHub в «Настройках».',
        if (project == null) 'Выберите ZIP-архив проекта.',
        if (analysis != null && !analysis!.canBuild) 'Проект не может быть собран — исправьте ошибки анализа.',
        if (!isNativeGradle && project != null) ...[
          if (Validators.appName(appName.text) case final e?) 'Название: $e',
          if (Validators.packageName(packageName.text) case final e?) 'Пакет: $e',
          if (Validators.versionName(versionName.text) case final e?) 'Версия: $e',
          if (Validators.versionCode(versionCode.text) case final e?) 'versionCode: $e',
        ],
        if (signing == SigningMode.keystore) ...[
          if (keystore == null) 'Выберите файл keystore.',
          ?keystoreFormatError,
          if (Validators.keystorePassword(storePassword.text) case final e?) 'Пароль хранилища: $e',
          ?Validators.keyAlias(keyAlias.text),
        ],
      ];

  Future<void> pickProject() async {
    final picked = await files.pickZip();
    if (picked == null) return;
    project = picked;
    analysis = null;
    projectIcon = null;
    projectIconBytes = null;
    projectError = null;
    analyzing = true;
    notifyListeners();
    try {
      final info = await compute(_readZip, picked.bytes);
      analysis = info.analysis;
      projectIcon = info.icon;
      projectIconBytes = info.iconBytes;
      _prefill(info.analysis);
    } on FormatException catch (e) {
      projectError = e.message;
    } catch (e) {
      projectError = 'Не удалось прочитать архив: $e';
    } finally {
      analyzing = false;
      notifyListeners();
    }
  }

  void clearProject() {
    project = null;
    analysis = null;
    projectIcon = null;
    projectIconBytes = null;
    projectError = null;
    notifyListeners();
  }

  void _prefill(ProjectAnalysis a) {
    final resolved = ResolvedAppConfig.resolve(a, const BuildOptions());
    appName.text = resolved.appName;
    packageName.text = resolved.packageName;
    versionName.text = resolved.versionName;
    versionCode.text = '${resolved.versionCode}';
    orientation = resolved.orientation;
    themeColor = resolved.themeColor;
    permissions = a.kind.isWeb ? resolved.permissions.where(AppPermission.webSupported.contains).toSet() : resolved.permissions;
  }

  Future<void> pickIcon() async {
    final picked = await files.pickImage();
    if (picked == null) return;
    iconError = validateIcon(picked.bytes);
    icon = iconError == null ? picked : null;
    notifyListeners();
  }

  void clearIcon() {
    icon = null;
    iconError = null;
    notifyListeners();
  }

  /// PNG, JPEG or WebP up to [maxIconBytes]; returns an error or null.
  static String? validateIcon(Uint8List bytes) {
    if (bytes.length > maxIconBytes) return 'Картинка больше 5 МБ — выберите файл поменьше.';
    bool starts(List<int> magic, [int offset = 0]) {
      if (bytes.length < offset + magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[offset + i] != magic[i]) return false;
      }
      return true;
    }

    final png = starts(const [0x89, 0x50, 0x4E, 0x47]);
    final jpeg = starts(const [0xFF, 0xD8, 0xFF]);
    final webp = starts(const [0x52, 0x49, 0x46, 0x46]) && starts(const [0x57, 0x45, 0x42, 0x50], 8);
    return png || jpeg || webp ? null : 'Это не PNG, JPEG или WebP.';
  }

  void setOrientation(ScreenOrientation value) {
    orientation = value;
    notifyListeners();
  }

  void togglePermission(AppPermission permission, bool enabled) {
    permissions = {...permissions};
    enabled ? permissions.add(permission) : permissions.remove(permission);
    notifyListeners();
  }

  void setSigning(SigningMode mode) {
    signing = mode;
    notifyListeners();
  }

  /// Parameter fields changed: re-run validation in the UI.
  void changed() => notifyListeners();

  /// Keystore fields changed: the previous check is no longer valid.
  void touch() {
    keystoreCheck = null;
    notifyListeners();
  }

  Future<void> pickKeystore() async {
    final picked = await files.pickKeystore();
    if (picked == null) return;
    keystore = picked;
    keystoreFormatError = Validators.keystoreBytes(picked.bytes.take(4).toList());
    keystoreCheck = null;
    notifyListeners();
  }

  KeystoreInput? get _keystoreInput {
    final ks = keystore;
    if (ks == null) return null;
    return KeystoreInput(
      bytes: ks.bytes,
      fileName: ks.name,
      storePassword: storePassword.text,
      alias: keyAlias.text.trim(),
      keyPassword: keyPassword.text.isEmpty ? storePassword.text : keyPassword.text,
    );
  }

  Future<void> validateKeystore(BuildBackend backend) async {
    final input = _keystoreInput;
    if (input == null) return;
    checkingKeystore = true;
    keystoreCheck = null;
    notifyListeners();
    try {
      keystoreCheck = await backend.validateKeystore(input);
    } on BackendException catch (e) {
      keystoreCheck = KeystoreValidation(valid: false, error: e.message);
    } finally {
      checkingKeystore = false;
      notifyListeners();
    }
  }

  BuildOptions get options => BuildOptions(
        appName: isNativeGradle ? null : appName.text.trim(),
        packageName: isNativeGradle ? null : packageName.text.trim(),
        versionName: isNativeGradle ? null : versionName.text.trim(),
        versionCode: isNativeGradle ? null : int.tryParse(versionCode.text.trim()),
        orientation: isNativeGradle ? null : orientation,
        permissions: isNativeGradle ? null : permissions,
        signing: signing,
      );

  String get _title => isNativeGradle || appName.text.trim().isEmpty ? 'Сборка APK' : 'Сборка «${appName.text.trim()}»';

  Future<void> startBuild(BuildBackend backend) async {
    final picked = project;
    if (picked == null) return;
    _stopPolling();
    _backend = backend;
    buildId = null;
    status = null;
    buildError = null;
    log.clear();
    _logIndex = 0;
    submitting = true;
    startedAt = DateTime.now();
    finishedAt = null;
    notifyListeners();
    try {
      final chosenIcon = iconSupported ? icon : null;
      buildId = await backend.submit(BuildSubmission(
        projectZip: picked.bytes,
        projectFileName: picked.name,
        options: options,
        keystore: signing == SigningMode.keystore ? _keystoreInput : null,
        icon: chosenIcon?.bytes,
        iconFileName: chosenIcon?.name,
      ));
      log.add('Сборка $buildId отправлена (${backend.mode.title}).');
      await bridge.requestNotifications();
      await bridge.watchStart(_title, 'Проект отправлен, ожидание сборщика…');
      _poll = Timer.periodic(backend.pollInterval, (_) => _refresh());
      unawaited(_refresh());
    } on BackendException catch (e) {
      buildError = e.message;
      finishedAt = DateTime.now();
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    final backend = _backend;
    final id = buildId;
    if (backend == null || id == null || _polling) return;
    _polling = true;
    try {
      final next = await backend.status(id, logFrom: _logIndex);
      log.addAll(next.logLines);
      if (log.length > 3000) log.removeRange(0, log.length - 3000);
      _logIndex = next.nextLogIndex;
      status = next;
      if (next.isFinished) {
        _stopPolling();
        finishedAt = DateTime.now();
        await _finished(backend, id, next);
      } else {
        final progress = stageProgress;
        await bridge.watchUpdate(
          _title,
          next.queuePosition != null ? 'В очереди, позиция ${next.queuePosition}' : (next.stageTitle ?? 'Сборка…'),
          progress: progress == null ? null : (progress * 100).round(),
        );
      }
    } on BackendException catch (e) {
      // Temporary network errors must not abort a long build.
      log.add('⚠ Нет ответа о статусе: ${e.message}');
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  Future<void> _finished(BuildBackend backend, String id, RemoteBuildStatus result) async {
    if (result.state == RemoteBuildState.succeeded) {
      // The system download notification takes over from here.
      await bridge.watchStop();
      await downloads?.download(backend, id);
    } else {
      await bridge.watchStop(title: 'Ошибка сборки', text: result.error ?? 'Подробности — в журнале сборки.');
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    _stopPolling();
    for (final c in [appName, packageName, versionName, versionCode, storePassword, keyAlias, keyPassword]) {
      c.dispose();
    }
    super.dispose();
  }
}
