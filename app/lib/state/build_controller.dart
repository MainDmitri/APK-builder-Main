import 'dart:async';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/apk_installer.dart';
import '../services/backend/build_backend.dart';
import '../services/file_service.dart';

ProjectAnalysis _analyzeZip(Uint8List bytes) => const ProjectAnalyzer().analyze(ZipMemorySource.fromBytes(bytes));

/// State of the "Build" screen: project, parameters, signing and the
/// running remote build.
class BuildController extends ChangeNotifier {
  BuildController({this.files = const FileService(), this.installer = const ApkInstaller()});

  final FileService files;
  final ApkInstaller installer;

  // ---------------------------------------------------------------- project
  PickedFile? project;
  ProjectAnalysis? analysis;
  String? projectError;
  bool analyzing = false;

  // -------------------------------------------------------------- parameters
  final appName = TextEditingController();
  final packageName = TextEditingController();
  final versionName = TextEditingController(text: '1.0.0');
  final versionCode = TextEditingController(text: '1');
  ScreenOrientation orientation = ScreenOrientation.sensor;
  Set<AppPermission> permissions = {AppPermission.internet};

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
  Timer? _poll;
  bool _polling = false;
  DownloadedApk? apk;
  bool downloading = false;

  bool get isNativeGradle => analysis?.kind == ProjectKind.nativeGradle;
  bool get isWeb => analysis?.kind.isWeb ?? false;
  bool get buildRunning => buildId != null && !(status?.isFinished ?? false) && buildError == null;

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
    projectError = null;
    analyzing = true;
    notifyListeners();
    try {
      analysis = await compute(_analyzeZip, picked.bytes);
      _prefill(analysis!);
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
    permissions = a.kind.isWeb ? resolved.permissions.where(AppPermission.webSupported.contains).toSet() : resolved.permissions;
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

  Future<void> startBuild(BuildBackend backend) async {
    final picked = project;
    if (picked == null) return;
    _stopPolling();
    _backend = backend;
    buildId = null;
    status = null;
    apk = null;
    buildError = null;
    log.clear();
    _logIndex = 0;
    submitting = true;
    notifyListeners();
    try {
      buildId = await backend.submit(BuildSubmission(
        projectZip: picked.bytes,
        projectFileName: picked.name,
        options: options,
        keystore: signing == SigningMode.keystore ? _keystoreInput : null,
      ));
      log.add('Сборка $buildId отправлена (${backend.mode.title}).');
      _poll = Timer.periodic(backend.pollInterval, (_) => _refresh());
      unawaited(_refresh());
    } on BackendException catch (e) {
      buildError = e.message;
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
      if (next.isFinished) _stopPolling();
    } on BackendException catch (e) {
      // Temporary network errors must not abort a long build.
      log.add('⚠ Нет ответа о статусе: ${e.message}');
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<String?> _ensureApk() async {
    if (apk != null) return null;
    final backend = _backend;
    final id = buildId;
    if (backend == null || id == null) return 'Нет готовой сборки.';
    downloading = true;
    notifyListeners();
    try {
      apk = await backend.downloadApk(id);
      return null;
    } on BackendException catch (e) {
      return e.message;
    } finally {
      downloading = false;
      notifyListeners();
    }
  }

  /// Saves the APK through the system dialog. Returns a message for the UI.
  Future<String> saveApk() async {
    final error = await _ensureApk();
    if (error != null) return error;
    final location = await files.save(apk!.fileName, apk!.bytes, mimeType: 'application/vnd.android.package-archive');
    return location == null ? 'Сохранение отменено' : 'APK сохранён: $location';
  }

  /// Opens the Android package installer. Returns an error message or null.
  Future<String?> installApk() async {
    final error = await _ensureApk();
    if (error != null) return error;
    return installer.install(apk!.bytes, apk!.fileName);
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
