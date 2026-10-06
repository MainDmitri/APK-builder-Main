import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:path/path.dart' as p;

import '../build_log.dart';
import '../config.dart';
import '../process_runner.dart';
import '../workspace.dart';

/// Stage 1 of the two-stage pipeline: `install` + `run build` with the
/// detected package manager, then locate the directory with index.html.
class NodeStage {
  NodeStage(this.config, {this.runner = const ProcessRunner()});

  final EngineConfig config;
  final ProcessRunner runner;

  /// Environment shared by install and build.
  static const Map<String, String> _baseEnv = {
    'BROWSER': 'none',
    'PUBLIC_URL': '.',
    'NEXT_TELEMETRY_DISABLED': '1',
    'NG_CLI_ANALYTICS': 'false',
    'NUXT_TELEMETRY_DISABLED': '1',
    'ASTRO_TELEMETRY_DISABLED': '1',
    'COREPACK_ENABLE_DOWNLOAD_PROMPT': '0',
    'COREPACK_ENABLE_STRICT': '0',
    'YARN_ENABLE_IMMUTABLE_INSTALLS': 'false',
    'npm_config_update_notifier': 'false',
    'npm_config_fund': 'false',
    'npm_config_audit': 'false',
  };

  /// Returns the absolute path of the built web root.
  Future<String> run(String projectDir, NodeProjectInfo info, BuildLog log, {void Function()? onBuildStart}) async {
    final nodeModules = p.join(projectDir, 'node_modules');
    if (Directory(nodeModules).existsSync()) {
      log.add('Удаляю node_modules из архива (зависимости ставятся заново под Linux).');
      deleteQuietly(nodeModules);
    }

    await runner.run(['node', '--version'], workingDirectory: projectDir, log: log, timeout: const Duration(seconds: 30));

    // NODE_ENV=production would skip devDependencies (vite, plugins…).
    const removeEnv = {'NODE_ENV'};
    final installEnv = {..._baseEnv, 'CI': 'true'};
    log.section('Установка зависимостей: ${info.installCommand.join(' ')}');
    final install = await runner.run(
      info.installCommand,
      workingDirectory: projectDir,
      log: log,
      environment: installEnv,
      removeEnvironment: removeEnv,
      timeout: config.nodeInstallTimeout,
    );
    if (install.exitCode != 0) {
      if (info.packageManager == PackageManager.npm && info.hasLockfile) {
        log.add('npm ci завершился ошибкой (lock-файл не совпадает с package.json?) — пробую npm install.');
        await runner.runChecked(
          ['npm', 'install', '--no-audit', '--no-fund'],
          workingDirectory: projectDir,
          log: log,
          environment: installEnv,
          removeEnvironment: removeEnv,
          timeout: config.nodeInstallTimeout,
          failureMessage: 'Не удалось установить npm-зависимости',
        );
      } else {
        throw BuildFailure('Не удалось установить зависимости (${info.installCommand.join(' ')}, код ${install.exitCode}).');
      }
    }

    onBuildStart?.call();
    log.section('Сборка веб-проекта: ${info.buildCommand.join(' ')}');
    await runner.runChecked(
      info.buildCommand,
      workingDirectory: projectDir,
      log: log,
      // CI=false: Create React App would otherwise turn lint warnings into errors.
      environment: {..._baseEnv, 'CI': 'false'},
      removeEnvironment: removeEnv,
      timeout: config.nodeBuildTimeout,
      failureMessage: 'Скрипт "build" завершился ошибкой',
    );

    final output = findOutputDir(projectDir, info.outputDirCandidates);
    if (output == null) {
      final existing = Directory(projectDir)
          .listSync()
          .whereType<Directory>()
          .map((d) => p.basename(d.path))
          .where((n) => n != 'node_modules' && !n.startsWith('.'))
          .join(', ');
      throw BuildFailure('После сборки не найден index.html. Проверены папки: '
          '${info.outputDirCandidates.join(', ')}. Есть папки: $existing. '
          'Укажите правильную папку в appbuilder.json → web.outputDir.');
    }
    log.add('Результат сборки: ${p.relative(output, from: projectDir)}/index.html');
    return output;
  }

  /// First candidate containing index.html; also looks one level deeper
  /// (e.g. Angular `dist/<project>/browser`).
  static String? findOutputDir(String projectDir, List<String> candidates) {
    for (final c in candidates) {
      final dir = p.normalize(p.join(projectDir, c));
      if (!p.isWithin(projectDir, dir)) continue;
      if (File(p.join(dir, 'index.html')).existsSync()) return dir;
    }
    for (final c in candidates) {
      final dir = Directory(p.join(projectDir, c));
      if (!dir.existsSync()) continue;
      for (final sub in dir.listSync().whereType<Directory>()) {
        for (final nested in [sub.path, p.join(sub.path, 'browser')]) {
          if (File(p.join(nested, 'index.html')).existsSync()) return nested;
        }
      }
    }
    return null;
  }
}
