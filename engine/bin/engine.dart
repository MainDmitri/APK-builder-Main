import 'dart:convert';
import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:appbuilder_engine/engine.dart';
import 'package:archive/archive_io.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>('appbuilder-engine', 'AppBuilder Engine — сборка APK из ZIP-проектов.')
    ..addCommand(ServeCommand())
    ..addCommand(BuildCommand())
    ..addCommand(AnalyzeCommand())
    ..addCommand(ContractCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(SelfTestCommand());
  try {
    final code = await runner.run(args) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}

class ServeCommand extends Command<int> {
  ServeCommand() {
    argParser
      ..addOption('port', help: 'HTTP-порт (по умолчанию PORT или 8080)')
      ..addOption('data', help: 'Каталог данных (по умолчанию APPBUILDER_DATA или ./data)');
  }

  @override
  String get name => 'serve';

  @override
  String get description => 'Запустить HTTP API движка.';

  @override
  Future<int> run() async {
    final config = EngineConfig.fromEnvironment(
      port: int.tryParse(argResults!['port'] as String? ?? ''),
      dataDir: argResults!['data'] as String?,
    );
    final server = EngineServer(config, BuildManager(config));
    final http = await server.start();
    stdout.writeln('AppBuilder Engine слушает http://${http.address.host}:${http.port} '
        '(данные: ${config.dataDir}, токен: ${config.token == null ? 'не задан' : 'задан'})');
    if (config.token == null) {
      stdout.writeln('ВНИМАНИЕ: ENGINE_TOKEN не задан — API доступен без авторизации.');
    }
    await ProcessSignal.sigint.watch().first.catchError((_) => ProcessSignal.sigint);
    await server.stop();
    return 0;
  }
}

class BuildCommand extends Command<int> {
  BuildCommand() {
    argParser
      ..addOption('out', abbr: 'o', help: 'Путь к итоговому APK или каталог')
      ..addOption('options', help: 'JSON с параметрами сборки (строка или @файл)')
      ..addOption('app-name')
      ..addOption('package')
      ..addOption('version-name')
      ..addOption('version-code')
      ..addOption('orientation', allowed: ScreenOrientation.values.map((o) => o.id))
      ..addOption('permissions', help: 'Через запятую: ${AppPermission.values.map((p) => p.id).join(',')}')
      ..addOption('keystore', help: 'Production keystore (.jks/.keystore/.p12)')
      ..addOption('key-alias')
      ..addOption('store-password-env', defaultsTo: 'APPBUILDER_STORE_PASSWORD', help: 'Переменная окружения с паролем хранилища')
      ..addOption('key-password-env', defaultsTo: 'APPBUILDER_KEY_PASSWORD', help: 'Переменная окружения с паролем ключа')
      ..addOption('work-dir', help: 'Рабочий каталог (по умолчанию временный)')
      ..addOption('result-json', help: 'Записать результат в JSON-файл');
  }

  @override
  String get name => 'build';

  @override
  String get description => 'Собрать APK из ZIP: build project.zip -o app.apk';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('Укажите один ZIP-архив.');
    final zip = File(rest.single);
    if (!zip.existsSync()) usageException('Файл не найден: ${zip.path}');
    final a = argResults!;

    var options = const BuildOptions();
    final rawOptions = a['options'] as String?;
    if (rawOptions != null) {
      final text = rawOptions.startsWith('@') ? File(rawOptions.substring(1)).readAsStringSync() : rawOptions;
      options = BuildOptions.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
    }
    final permissions = (a['permissions'] as String?)
        ?.split(',')
        .map(AppPermission.tryParse)
        .whereType<AppPermission>()
        .toSet();
    KeystoreSpec? keystore;
    final ksPath = a['keystore'] as String?;
    if (ksPath != null && ksPath.isNotEmpty) {
      final storePassword = Platform.environment[a['store-password-env'] as String] ?? '';
      final keyPassword = Platform.environment[a['key-password-env'] as String] ?? storePassword;
      keystore = KeystoreSpec(
        path: File(ksPath).absolute.path,
        storePassword: storePassword,
        alias: a['key-alias'] as String? ?? '',
        keyPassword: keyPassword.isEmpty ? storePassword : keyPassword,
      );
    }
    options = BuildOptions(
      appName: a['app-name'] as String? ?? options.appName,
      packageName: a['package'] as String? ?? options.packageName,
      versionName: a['version-name'] as String? ?? options.versionName,
      versionCode: int.tryParse(a['version-code'] as String? ?? '') ?? options.versionCode,
      orientation: ScreenOrientation.tryParse(a['orientation'] as String?) ?? options.orientation,
      permissions: permissions ?? options.permissions,
      signing: keystore == null ? SigningMode.debug : SigningMode.keystore,
    );

    final config = EngineConfig.fromEnvironment();
    final workDir = a['work-dir'] as String? ?? (await Directory.systemTemp.createTemp('appbuilder-build')).path;
    final log = BuildLog(File(p.join(workDir, 'build.log')), echo: true);
    final resultPath = a['result-json'] as String?;
    try {
      final outcome = await BuildPipeline(config).run(
        BuildRequest(zipPath: zip.absolute.path, workDir: workDir, options: options, keystore: keystore),
        log,
      );
      var target = a['out'] as String? ?? outcome.fileName;
      if (Directory(target).existsSync() || target.endsWith('/')) target = p.join(target, outcome.fileName);
      File(target).parent.createSync(recursive: true);
      File(outcome.apkPath).copySync(target);
      stdout.writeln('APK: ${File(target).absolute.path}');
      if (resultPath != null) {
        File(resultPath).writeAsStringSync(jsonEncode({
          'success': true,
          'apk': File(target).absolute.path,
          ...outcome.toJson(),
          'analysis': outcome.analysis.toJson(),
        }));
      }
      return 0;
    } on BuildFailure catch (e) {
      stderr.writeln('ОШИБКА СБОРКИ: ${e.message}');
      if (resultPath != null) {
        File(resultPath).writeAsStringSync(jsonEncode({'success': false, 'error': e.message}));
      }
      return 1;
    } finally {
      await log.close();
    }
  }
}

class AnalyzeCommand extends Command<int> {
  @override
  String get name => 'analyze';

  @override
  String get description => 'Определить тип проекта в ZIP и вывести план сборки (JSON).';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) usageException('Укажите один ZIP-архив.');
    final analysis = const ProjectAnalyzer().analyze(ZipMemorySource.fromBytes(File(rest.single).readAsBytesSync()));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'analysis': analysis.toJson(),
      if (analysis.kind != ProjectKind.unsupported)
        'resolved': ResolvedAppConfig.resolve(analysis, const BuildOptions()).toJson(),
    }));
    return analysis.canBuild ? 0 : 2;
  }
}

class ContractCommand extends Command<int> {
  ContractCommand() {
    argParser.addOption('out', abbr: 'o', help: 'Записать в файл вместо stdout');
  }

  @override
  String get name => 'contract';

  @override
  String get description => 'Вывести контракт для ИИ (agent-contract.md).';

  @override
  Future<int> run() async {
    final out = argResults!['out'] as String?;
    if (out == null) {
      stdout.write(buildAgentContract());
    } else {
      File(out).writeAsStringSync(buildAgentContract());
    }
    return 0;
  }
}

class DoctorCommand extends Command<int> {
  @override
  String get name => 'doctor';

  @override
  String get description => 'Проверить установленные инструменты.';

  @override
  Future<int> run() async {
    final tools = await EngineDoctor(EngineConfig.fromEnvironment()).check();
    for (final t in tools) {
      stdout.writeln('${t.ok ? '✔' : (t.required ? '✖' : '–')} ${t.name.padRight(14)} ${t.detail}');
    }
    return tools.any((t) => t.required && !t.ok) ? 1 : 0;
  }
}

/// Builds every sample project (each subdirectory of --samples) end to end,
/// signing the first one with a freshly generated production keystore.
class SelfTestCommand extends Command<int> {
  SelfTestCommand() {
    argParser
      ..addOption('samples', defaultsTo: 'samples', help: 'Каталог с примерами проектов')
      ..addOption('out', defaultsTo: 'selftest-out', help: 'Куда сложить APK и логи')
      ..addMultiOption('only', help: 'Собрать только указанные примеры');
  }

  @override
  String get name => 'selftest';

  @override
  String get description => 'Собрать все примеры из samples/ (сквозная проверка движка).';

  @override
  Future<int> run() async {
    final samplesDir = Directory(argResults!['samples'] as String);
    final outDir = Directory(argResults!['out'] as String)..createSync(recursive: true);
    final only = (argResults!['only'] as List<String>).toSet();
    final config = EngineConfig.fromEnvironment();
    final samples = samplesDir.listSync().whereType<Directory>().where((d) => only.isEmpty || only.contains(p.basename(d.path))).toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (samples.isEmpty) usageException('В ${samplesDir.path} нет примеров.');

    final results = <String, String>{};
    var first = true;
    for (final sample in samples) {
      final name = p.basename(sample.path);
      final work = await Directory.systemTemp.createTemp('appbuilder-selftest-$name');
      final zipPath = p.join(work.path, '$name.zip');
      final encoder = ZipFileEncoder()..create(zipPath);
      await encoder.addDirectory(sample, includeDirName: false);
      await encoder.close();

      final log = BuildLog(File(p.join(outDir.path, '$name.log')));
      KeystoreSpec? keystore;
      if (first) {
        keystore = await _productionKeystore(work.path, log);
        first = false;
      }
      stdout.writeln('▶ $name ${keystore == null ? '(debug key)' : '(production keystore)'}');
      try {
        final outcome = await BuildPipeline(config).run(
          BuildRequest(zipPath: zipPath, workDir: p.join(work.path, 'build'), keystore: keystore),
          log,
          onStage: (s) => stdout.writeln('   · ${s.title}'),
        );
        File(outcome.apkPath).copySync(p.join(outDir.path, '$name.apk'));
        results[name] = 'OK  ${outcome.analysis.kind.id}  ${(outcome.size / 1024).round()} KB  '
            'схемы: ${outcome.signingSchemes.join('+')}';
      } on BuildFailure catch (e) {
        results[name] = 'FAIL ${e.message.split('\n').first}';
        stdout.writeln(log.tail(80).join('\n'));
      } finally {
        await log.close();
        await work.delete(recursive: true);
      }
      stdout.writeln('   ${results[name]}');
    }
    stdout.writeln('\nИтог:');
    results.forEach((k, v) => stdout.writeln('  $k: $v'));
    return results.values.every((v) => v.startsWith('OK')) ? 0 : 1;
  }

  Future<KeystoreSpec> _productionKeystore(String dir, BuildLog log) async {
    final path = p.join(dir, 'selftest.jks');
    const runner = ProcessRunner();
    await runner.runChecked(
      [
        'keytool', '-genkeypair', '-noprompt', '-keystore', path, '-storetype', 'JKS', //
        '-storepass', 'selftest-store', '-keypass', 'selftest-key', '-alias', 'release',
        '-keyalg', 'RSA', '-keysize', '2048', '-validity', '365', '-dname', 'CN=AppBuilder Selftest,O=AppBuilder,C=RU',
      ],
      workingDirectory: dir,
      log: log,
      failureMessage: 'keytool не смог создать тестовый keystore',
    );
    return KeystoreSpec(path: path, storePassword: 'selftest-store', alias: 'release', keyPassword: 'selftest-key');
  }
}
