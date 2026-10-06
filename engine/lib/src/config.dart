import 'dart:io';

import 'package:path/path.dart' as p;

/// Engine configuration, read from environment variables (Docker) with
/// sensible defaults for running from a source checkout.
class EngineConfig {
  EngineConfig({
    required this.dataDir,
    required this.templatesDir,
    required this.androidHome,
    required this.gradleCommand,
    this.buildToolsDirOverride,
    this.port = 8080,
    this.token,
    this.maxParallelBuilds = 1,
    this.maxUploadBytes = 200 * 1024 * 1024,
    this.retention = const Duration(hours: 24),
    this.nodeInstallTimeout = const Duration(minutes: 15),
    this.nodeBuildTimeout = const Duration(minutes: 15),
    this.gradleTimeout = const Duration(minutes: 30),
    this.maxExtractedBytes = 1024 * 1024 * 1024,
    this.maxArchiveEntries = 20000,
  });

  /// Builds, debug keystore, Gradle cache.
  final String dataDir;

  /// Android project templates (web_shell, native, engine-init.gradle).
  final String templatesDir;
  final String androidHome;

  /// Gradle executable used when a project has no usable wrapper.
  final String gradleCommand;
  final String? buildToolsDirOverride;
  final int port;

  /// Bearer token required for /api/* (null = no auth).
  final String? token;
  final int maxParallelBuilds;
  final int maxUploadBytes;
  final Duration retention;
  final Duration nodeInstallTimeout;
  final Duration nodeBuildTimeout;
  final Duration gradleTimeout;
  final int maxExtractedBytes;
  final int maxArchiveEntries;

  String get buildsDir => p.join(dataDir, 'builds');
  String get keysDir => p.join(dataDir, 'keys');
  String get debugKeystorePath => p.join(keysDir, 'debug.keystore');

  /// Gradle cache shared by all builds (can be overridden by GRADLE_USER_HOME).
  String get gradleUserHome => Platform.environment['GRADLE_USER_HOME'] ?? p.join(dataDir, 'gradle-home');

  /// Highest installed build-tools version (zipalign, apksigner).
  String? get buildToolsDir {
    if (buildToolsDirOverride != null) return buildToolsDirOverride;
    final dir = Directory(p.join(androidHome, 'build-tools'));
    if (!dir.existsSync()) return null;
    final versions = dir.listSync().whereType<Directory>().map((d) => p.basename(d.path)).toList()
      ..sort(_compareVersions);
    return versions.isEmpty ? null : p.join(dir.path, versions.last);
  }

  String? get zipalignPath => buildToolsDir == null ? null : p.join(buildToolsDir!, 'zipalign');
  String? get apksignerPath => buildToolsDir == null ? null : p.join(buildToolsDir!, 'apksigner');

  factory EngineConfig.fromEnvironment({int? port, String? dataDir}) {
    final env = Platform.environment;
    final androidHome = env['ANDROID_HOME'] ?? env['ANDROID_SDK_ROOT'] ?? p.join(env['HOME'] ?? '/root', 'Android', 'Sdk');
    return EngineConfig(
      dataDir: dataDir ?? env['APPBUILDER_DATA'] ?? p.join(Directory.current.path, 'data'),
      templatesDir: env['APPBUILDER_TEMPLATES'] ?? _defaultTemplatesDir(),
      androidHome: androidHome,
      gradleCommand: env['APPBUILDER_GRADLE'] ?? 'gradle',
      buildToolsDirOverride: env['APPBUILDER_BUILD_TOOLS'],
      port: port ?? int.tryParse(env['PORT'] ?? '') ?? 8080,
      token: (env['ENGINE_TOKEN']?.isNotEmpty ?? false) ? env['ENGINE_TOKEN'] : null,
      maxParallelBuilds: int.tryParse(env['MAX_PARALLEL_BUILDS'] ?? '') ?? 1,
      maxUploadBytes: (int.tryParse(env['MAX_UPLOAD_MB'] ?? '') ?? 200) * 1024 * 1024,
      retention: Duration(hours: int.tryParse(env['BUILD_RETENTION_HOURS'] ?? '') ?? 24),
    );
  }

  /// `templates/` next to the engine sources (source checkout) or next to a
  /// compiled executable.
  static String _defaultTemplatesDir() {
    final candidates = [
      p.join(Directory.current.path, 'templates'),
      p.join(p.dirname(p.dirname(Platform.script.toFilePath())), 'templates'),
      p.join(p.dirname(Platform.resolvedExecutable), 'templates'),
    ];
    return candidates.firstWhere((c) => Directory(c).existsSync(), orElse: () => candidates.first);
  }

  static int _compareVersions(String a, String b) {
    final pa = a.split(RegExp(r'[.\-]')).map((s) => int.tryParse(s) ?? -1).toList();
    final pb = b.split(RegExp(r'[.\-]')).map((s) => int.tryParse(s) ?? -1).toList();
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
    }
    return pa.length.compareTo(pb.length);
  }
}
