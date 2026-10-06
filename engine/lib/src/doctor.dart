import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';

import 'config.dart';

class ToolStatus {
  const ToolStatus(this.name, this.ok, this.detail, {this.required = true});

  final String name;
  final bool ok;
  final String detail;
  final bool required;

  Map<String, Object?> toJson() => {'name': name, 'ok': ok, 'detail': detail, 'required': required};
}

/// Checks that every external tool of the pipeline is installed.
class EngineDoctor {
  EngineDoctor(this.config);

  final EngineConfig config;

  Future<List<ToolStatus>> check() async {
    final buildTools = config.buildToolsDir;
    return [
      await _version('node', ['node', '--version']),
      await _version('npm', ['npm', '--version']),
      await _version('pnpm', ['pnpm', '--version'], required: false),
      await _version('yarn', ['yarn', '--version'], required: false),
      await _version('java', ['java', '-version']),
      await _version('keytool', ['keytool', '-help'], firstLineOnly: true, okExitCodes: const {0, 1}, detailOverride: 'ok'),
      await _version('gradle', [config.gradleCommand, '--version', '--quiet'], pattern: RegExp(r'Gradle\s+\S+')),
      ToolStatus('android-sdk', Directory(config.androidHome).existsSync(), config.androidHome),
      ToolStatus('build-tools', buildTools != null, buildTools ?? 'не найдены в ${config.androidHome}/build-tools'),
      ToolStatus('zipalign', config.zipalignPath != null && File(config.zipalignPath!).existsSync(), config.zipalignPath ?? '-'),
      ToolStatus('apksigner', config.apksignerPath != null && File(config.apksignerPath!).existsSync(), config.apksignerPath ?? '-'),
      ToolStatus('templates', Directory(config.templatesDir).existsSync(), config.templatesDir),
      await _version('rsvg-convert', ['rsvg-convert', '--version'], required: false),
    ];
  }

  Future<ToolStatus> _version(
    String name,
    List<String> command, {
    bool required = true,
    bool firstLineOnly = true,
    RegExp? pattern,
    Set<int> okExitCodes = const {0},
    String? detailOverride,
  }) async {
    try {
      final r = await Process.run(command.first, command.sublist(1), runInShell: Platform.isWindows)
          .timeout(const Duration(seconds: 90));
      final text = '${r.stdout}\n${r.stderr}'.trim();
      final ok = okExitCodes.contains(r.exitCode);
      var detail = pattern?.firstMatch(text)?.group(0) ?? (firstLineOnly ? text.split('\n').first.trim() : text);
      if (ok && detailOverride != null) detail = detailOverride;
      return ToolStatus(name, ok, detail, required: required);
    } on Object catch (e) {
      return ToolStatus(name, false, 'не найден ($e)', required: required);
    }
  }

  static Map<String, Object?> toolchainJson() => {
        'contractVersion': Toolchain.contractVersion,
        'androidGradlePlugin': Toolchain.androidGradlePlugin,
        'kotlin': Toolchain.kotlin,
        'gradle': Toolchain.gradle,
        'compileSdk': Toolchain.compileSdk,
        'targetSdk': Toolchain.targetSdk,
        'minSdk': Toolchain.minSdk,
        'buildTools': Toolchain.buildTools,
        'java': Toolchain.java,
        'node': Toolchain.nodeMajor,
      };
}
