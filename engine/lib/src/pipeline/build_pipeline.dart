import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../build_log.dart';
import '../config.dart';
import '../process_runner.dart';
import '../workspace.dart';
import 'gradle_stage.dart';
import 'native_sources.dart';
import 'node_stage.dart';
import 'signer.dart';
import 'web_shell.dart';

class BuildRequest {
  const BuildRequest({
    required this.zipPath,
    required this.workDir,
    this.options = const BuildOptions(),
    this.keystore,
    this.iconPath,
  });

  final String zipPath;

  /// Per-build working directory; the signed APK ends up in `<workDir>/out`.
  final String workDir;
  final BuildOptions options;

  /// Production keystore; `null` → engine debug key.
  final KeystoreSpec? keystore;

  /// Launcher icon picture chosen by the user (PNG, JPEG, WebP, GIF, BMP or
  /// SVG); replaces the project's own icon.
  final String? iconPath;
}

class BuildOutcome {
  const BuildOutcome({
    required this.apkPath,
    required this.fileName,
    required this.size,
    required this.sha256,
    required this.analysis,
    required this.app,
    required this.signingSchemes,
    this.certificateSha256,
  });

  final String apkPath;
  final String fileName;
  final int size;
  final String sha256;
  final ProjectAnalysis analysis;
  final ResolvedAppConfig app;
  final List<String> signingSchemes;
  final String? certificateSha256;

  Map<String, Object?> toJson() => {
        'fileName': fileName,
        'size': size,
        'sha256': sha256,
        'signingSchemes': signingSchemes,
        if (certificateSha256 != null) 'certificateSha256': certificateSha256,
        'app': app.toJson(),
      };
}

/// The whole AppBuilder pipeline: analyze → (npm) → Android project → Gradle
/// → zipalign → apksigner → verify.
class BuildPipeline {
  BuildPipeline(this.config, {this.runner = const ProcessRunner()});

  final EngineConfig config;
  final ProcessRunner runner;

  Future<BuildOutcome> run(
    BuildRequest request,
    BuildLog log, {
    void Function(BuildStage stage)? onStage,
    void Function(ProjectAnalysis analysis)? onAnalysis,
  }) async {
    final work = request.workDir;
    final srcDir = p.join(work, 'src');
    final androidDir = p.join(work, 'android');
    final outDir = p.join(work, 'out');
    for (final d in [srcDir, androidDir, outDir]) {
      deleteQuietly(d);
    }
    Directory(srcDir).createSync(recursive: true);
    final signer = ApkSigner(config, runner: runner);

    try {
      onStage?.call(BuildStage.extract);
      log.section('Распаковка и анализ');
      final skipped = await extractZipSafely(
        request.zipPath,
        srcDir,
        maxBytes: config.maxExtractedBytes,
        maxEntries: config.maxArchiveEntries,
      );
      if (skipped.isNotEmpty) log.add('Пропущены символические ссылки: ${skipped.join(', ')}');

      var analysis = const ProjectAnalyzer().analyze(DirectorySource(srcDir));
      final projectDir = p.normalize(p.join(srcDir, analysis.rootPrefix));
      log.add('Тип проекта: ${analysis.kind.title}');
      for (final w in analysis.warnings) {
        log.add('⚠ $w');
      }
      onAnalysis?.call(analysis);
      if (!analysis.canBuild) {
        for (final e in analysis.errors) {
          log.add('✖ $e');
        }
        throw BuildFailure('Проект не может быть собран:\n- ${analysis.errors.join('\n- ')}');
      }

      // Fail fast on a wrong keystore before spending minutes on Gradle.
      final keystore = request.keystore;
      if (keystore != null) {
        log.section('Проверка keystore');
        final check = await signer.validate(keystore, log);
        if (!check.valid) throw BuildFailure('Keystore: ${check.error}');
        log.add('Keystore OK: ${check.storeType ?? ''} ${check.owner ?? ''}');
      }

      final customIcon = request.iconPath;
      if (customIcon != null) {
        log.add(analysis.kind == ProjectKind.nativeGradle
            ? 'Выбранная иконка не применяется к Gradle-проекту — иконка берётся из его ресурсов.'
            : 'Иконка приложения: картинка, выбранная при сборке.');
      }

      var app = ResolvedAppConfig.resolve(analysis, request.options);
      String unsignedApk;
      final gradle = GradleStage(config, runner: runner);

      switch (analysis.kind) {
        case ProjectKind.nodeProject:
        case ProjectKind.staticWeb:
          var webRoot = projectDir;
          if (analysis.kind == ProjectKind.nodeProject) {
            onStage?.call(BuildStage.nodeInstall);
            webRoot = await NodeStage(config, runner: runner).run(
              projectDir,
              analysis.node!,
              log,
              onBuildStart: () => onStage?.call(BuildStage.nodeBuild),
            );
          }
          onStage?.call(BuildStage.webAssets);
          final source = DirectorySource(webRoot);
          final webWarnings = <String>[];
          final webInfo = ProjectAnalyzer.inspectWebRoot(source.paths.toSet(), source.readText, webWarnings);
          if (analysis.kind == ProjectKind.nodeProject) {
            for (final w in webWarnings) {
              log.add('⚠ $w');
            }
            analysis = analysis.withWebRoot(
              manifest: webInfo.manifest,
              manifestPath: webInfo.manifestPath,
              extraWarnings: webWarnings,
            );
            onAnalysis?.call(analysis);
            app = ResolvedAppConfig.resolve(analysis, request.options);
          }
          _validate(app);
          log.add('Приложение: ${app.appName} (${app.packageName}) ${app.versionName}/${app.versionCode}, '
              'ориентация ${app.orientation.id}, разрешения: ${app.permissions.map((e) => e.id).join(', ')}');
          onStage?.call(BuildStage.androidProject);
          log.section('Генерация WebView-оболочки');
          await WebShellGenerator(config).generate(
            webRoot: webRoot,
            androidDir: androidDir,
            app: app,
            webInfo: webInfo,
            log: log,
            customIcon: customIcon,
          );
          onStage?.call(BuildStage.gradle);
          log.section('Gradle assembleRelease');
          unsignedApk = await gradle.assembleRelease(projectDir: androidDir, log: log, appModule: 'app');

        case ProjectKind.nativeSources:
          _validate(app);
          onStage?.call(BuildStage.androidProject);
          log.section('Генерация Gradle-проекта для исходников');
          await NativeSourcesGenerator(config).generate(
            projectDir: projectDir,
            androidDir: androidDir,
            analysis: analysis,
            app: app,
            log: log,
            customIcon: customIcon,
          );
          onStage?.call(BuildStage.gradle);
          log.section('Gradle assembleRelease');
          unsignedApk = await gradle.assembleRelease(projectDir: androidDir, log: log, appModule: 'app');

        case ProjectKind.nativeGradle:
          final info = analysis.native!;
          onStage?.call(BuildStage.gradle);
          log.section('Gradle assembleRelease (проект пользователя)');
          if (request.options.packageName != null || request.options.versionName != null) {
            log.add('Gradle-проект: пакет и версия берутся из build.gradle проекта, параметры сборки для них не применяются.');
          }
          unsignedApk = await gradle.assembleRelease(
            projectDir: projectDir,
            log: log,
            useWrapper: info.hasUsableWrapper,
            applyInitScript: true,
            appModule: info.appModule,
          );

        case ProjectKind.unsupported:
          throw BuildFailure('Тип проекта не распознан.');
      }

      final baseName = analysis.kind == ProjectKind.nativeGradle
          ? (request.options.appName ?? analysis.native?.applicationId?.split('.').last ?? 'app')
          : app.appName;
      final version = analysis.kind == ProjectKind.nativeGradle ? (request.options.versionName ?? 'release') : app.versionName;
      final fileName = '${_safeFileName(baseName)}-${_safeFileName(version)}.apk';
      final aligned = p.join(outDir, 'aligned.apk');
      final output = p.join(outDir, fileName);

      onStage?.call(BuildStage.zipalign);
      log.section('zipalign');
      await signer.align(input: unsignedApk, output: aligned, log: log);

      onStage?.call(BuildStage.sign);
      log.section('Подпись APK');
      final ks = keystore ?? await signer.debugKeystore(log);
      log.add(keystore == null ? 'Ключ: debug (androiddebugkey)' : 'Ключ: production, alias ${ks.alias}');
      await signer.sign(input: aligned, output: output, keystore: ks, log: log);
      File(aligned).deleteSync();

      onStage?.call(BuildStage.verify);
      log.section('Проверка подписи');
      final verified = await signer.verify(apk: output, log: log);
      log.add('Схемы подписи: ${verified.schemes.join(', ')}');

      final bytes = File(output).readAsBytesSync();
      final outcome = BuildOutcome(
        apkPath: output,
        fileName: fileName,
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
        analysis: analysis,
        app: app,
        signingSchemes: verified.schemes,
        certificateSha256: verified.certificateSha256,
      );
      log.section('Готово: $fileName (${(bytes.length / 1024 / 1024).toStringAsFixed(2)} МБ)');
      return outcome;
    } finally {
      if (Platform.environment['APPBUILDER_KEEP_WORKDIR'] != '1') {
        deleteQuietly(srcDir);
        deleteQuietly(androidDir);
      }
    }
  }

  static void _validate(ResolvedAppConfig app) {
    final errors = app.validate();
    if (errors.isNotEmpty) throw BuildFailure('Некорректные параметры приложения:\n- ${errors.join('\n- ')}');
  }

  static String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '').replaceAll(RegExp(r'\s+'), '-').trim();
    return cleaned.isEmpty ? 'app' : cleaned;
  }
}
