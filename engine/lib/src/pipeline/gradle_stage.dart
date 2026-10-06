import 'dart:io';

import 'package:path/path.dart' as p;

import '../build_log.dart';
import '../config.dart';
import '../process_runner.dart';

/// Runs `assembleRelease` and locates the unsigned release APK.
class GradleStage {
  GradleStage(this.config, {this.runner = const ProcessRunner()});

  final EngineConfig config;
  final ProcessRunner runner;

  Future<String> assembleRelease({
    required String projectDir,
    required BuildLog log,
    bool useWrapper = false,
    bool applyInitScript = false,
    String? appModule,
  }) async {
    final sdkDir = config.androidHome.replaceAll(r'\', r'\\');
    File(p.join(projectDir, 'local.properties')).writeAsStringSync('sdk.dir=$sdkDir\n');

    final List<String> executable;
    if (useWrapper) {
      final wrapper = p.join(projectDir, Platform.isWindows ? 'gradlew.bat' : 'gradlew');
      if (!Platform.isWindows) await Process.run('chmod', ['+x', wrapper]);
      executable = [wrapper];
    } else {
      executable = [config.gradleCommand];
    }

    final command = [
      ...executable,
      '--no-daemon',
      '--console=plain',
      '--warning-mode=summary',
      if (applyInitScript) ...['--init-script', p.join(config.templatesDir, 'engine-init.gradle')],
      'assembleRelease',
    ];
    final result = await runner.run(
      command,
      workingDirectory: projectDir,
      log: log,
      environment: {
        'ANDROID_HOME': config.androidHome,
        'ANDROID_SDK_ROOT': config.androidHome,
        'GRADLE_USER_HOME': config.gradleUserHome,
      },
      timeout: config.gradleTimeout,
    );
    if (result.exitCode != 0) {
      throw BuildFailure('Gradle: сборка завершилась ошибкой.\n${summarizeGradleErrors(result.output)}');
    }

    final apk = findReleaseApk(projectDir, appModule: appModule);
    if (apk == null) throw BuildFailure('Gradle завершился успешно, но release-APK не найден в build/outputs/apk/.');
    log.add('Собран: ${p.relative(apk, from: projectDir)}');
    return apk;
  }

  /// Release APK of the app module; prefers `*-unsigned.apk` and universal
  /// splits.
  static String? findReleaseApk(String projectDir, {String? appModule}) {
    final candidates = <File>[];
    for (final e in Directory(projectDir).listSync(recursive: true, followLinks: false)) {
      if (e is! File || !e.path.endsWith('.apk')) continue;
      final rel = p.relative(e.path, from: projectDir).replaceAll('\\', '/');
      if (rel.contains('/build/outputs/apk/') && rel.contains('release') && !rel.contains('androidTest')) {
        candidates.add(e);
      }
    }
    if (candidates.isEmpty) return null;
    int score(File f) {
      final rel = p.relative(f.path, from: projectDir).replaceAll('\\', '/');
      var s = 0;
      if (appModule != null && (appModule.isEmpty ? rel.startsWith('build/') : rel.startsWith('$appModule/'))) s += 100;
      if (rel.contains('universal')) s += 10;
      if (rel.endsWith('-unsigned.apk')) s += 5;
      return s;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates.first.path;
  }

  /// Extracts the meaningful part of a Gradle failure for the user.
  static String summarizeGradleErrors(List<String> output) {
    final picked = <String>[];
    for (var i = 0; i < output.length; i++) {
      final line = output[i];
      final compilerError = line.startsWith('e: ') || line.contains(': error:') || line.contains('ERROR:') ||
          line.contains('AAPT: error') || line.startsWith('error: ');
      if (compilerError && picked.length < 15) picked.add(line.trim());
      if (line.startsWith('* What went wrong:')) {
        picked.add('What went wrong:');
        for (var j = i + 1; j < output.length && j < i + 12; j++) {
          if (output[j].startsWith('* Try:')) break;
          if (output[j].trim().isNotEmpty) picked.add(output[j].trim());
        }
      }
    }
    final text = picked.isEmpty ? output.skip(output.length > 25 ? output.length - 25 : 0).join('\n') : picked.join('\n');
    return text.length > 3000 ? '${text.substring(0, 3000)}…' : text;
  }
}
