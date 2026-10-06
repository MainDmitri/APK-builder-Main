import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:path/path.dart' as p;

import '../build_log.dart';
import '../config.dart';
import '../pipeline/build_pipeline.dart';
import '../pipeline/signer.dart';
import '../process_runner.dart';
import '../workspace.dart';

enum BuildState { queued, running, succeeded, failed }

/// One build, persisted as `<buildsDir>/<id>/state.json`.
class BuildRecord {
  BuildRecord({
    required this.id,
    required this.dir,
    required this.createdAt,
    required this.options,
    required this.log,
    this.state = BuildState.queued,
  });

  final String id;
  final String dir;
  final DateTime createdAt;
  final BuildOptions options;
  final BuildLog log;
  BuildState state;
  BuildStage? stage;
  ProjectKind? kind;
  DateTime? startedAt;
  DateTime? finishedAt;
  String? error;
  Map<String, Object?>? analysis;
  Map<String, Object?>? result;
  String? apkPath;

  String get zipPath => p.join(dir, 'input.zip');
  String get keystorePath => p.join(dir, 'keystore.bin');

  Map<String, Object?> toJson({int? logFrom}) => {
        'id': id,
        'state': state.name,
        if (stage != null) 'stage': stage!.name,
        if (stage != null) 'stageTitle': stage!.title,
        if (kind != null) 'stages': BuildPlan.forKind(kind!).stages.map((s) => {'id': s.name, 'title': s.title}).toList(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (startedAt != null) 'startedAt': startedAt!.toUtc().toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toUtc().toIso8601String(),
        if (error != null) 'error': error,
        'options': options.toJson(),
        if (analysis != null) 'analysis': analysis,
        if (result != null) 'result': result,
        if (logFrom != null)
          'log': {
            'from': logFrom,
            'lines': log.linesFrom(logFrom),
            'next': log.length,
          },
      };

  void persist() {
    final json = toJson()..['kind'] = kind?.id;
    File(p.join(dir, 'state.json')).writeAsStringSync(jsonEncode(json));
  }

  static BuildRecord? load(String dir) {
    final file = File(p.join(dir, 'state.json'));
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final record = BuildRecord(
        id: json['id'] as String,
        dir: dir,
        createdAt: DateTime.parse(json['createdAt'] as String),
        options: BuildOptions.fromJson((json['options'] as Map).cast<String, Object?>()),
        log: BuildLog.readOnly(File(p.join(dir, 'build.log'))),
        state: BuildState.values.byName(json['state'] as String),
      );
      record
        ..stage = json['stage'] == null ? null : BuildStage.values.byName(json['stage'] as String)
        ..kind = ProjectKind.values.where((k) => k.id == json['kind']).firstOrNull
        ..startedAt = json['startedAt'] == null ? null : DateTime.parse(json['startedAt'] as String)
        ..finishedAt = json['finishedAt'] == null ? null : DateTime.parse(json['finishedAt'] as String)
        ..error = json['error'] as String?
        ..analysis = (json['analysis'] as Map?)?.cast<String, Object?>()
        ..result = (json['result'] as Map?)?.cast<String, Object?>();
      final fileName = record.result?['fileName'] as String?;
      if (fileName != null) record.apkPath = p.join(dir, 'out', fileName);
      return record;
    } on Object {
      return null;
    }
  }
}

/// Queue with limited parallelism, persistence and retention cleanup.
class BuildManager {
  BuildManager(this.config, {BuildPipeline? pipeline}) : pipeline = pipeline ?? BuildPipeline(config);

  final EngineConfig config;
  final BuildPipeline pipeline;
  final Map<String, BuildRecord> _builds = {};
  final Map<String, KeystoreSpec> _keystores = {};
  final List<String> _queue = [];
  int _running = 0;
  Timer? _cleanup;
  final _random = Random.secure();

  int get running => _running;
  int get queued => _queue.length;

  void start() {
    Directory(config.buildsDir).createSync(recursive: true);
    for (final dir in Directory(config.buildsDir).listSync().whereType<Directory>()) {
      final record = BuildRecord.load(dir.path);
      if (record == null) continue;
      if (record.state == BuildState.queued || record.state == BuildState.running) {
        record
          ..state = BuildState.failed
          ..error = 'Сборка прервана перезапуском движка.'
          ..finishedAt = DateTime.now()
          ..persist();
        deleteQuietly(record.keystorePath);
      }
      _builds[record.id] = record;
    }
    _removeExpired();
    _cleanup = Timer.periodic(const Duration(minutes: 30), (_) => _removeExpired());
  }

  Future<void> dispose() async {
    _cleanup?.cancel();
  }

  String _newId() {
    final ts = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final rnd = List.generate(4, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return '$ts-$rnd';
  }

  /// Takes ownership of [uploadedZip] (moved into the build directory).
  BuildRecord submit({
    required File uploadedZip,
    required BuildOptions options,
    File? uploadedKeystore,
    String? storePassword,
    String? keyAlias,
    String? keyPassword,
  }) {
    final id = _newId();
    final dir = p.join(config.buildsDir, id);
    Directory(dir).createSync(recursive: true);
    final record = BuildRecord(
      id: id,
      dir: dir,
      createdAt: DateTime.now(),
      options: options,
      log: BuildLog(File(p.join(dir, 'build.log'))),
    );
    _move(uploadedZip, record.zipPath);
    if (uploadedKeystore != null) {
      _move(uploadedKeystore, record.keystorePath);
      _keystores[id] = KeystoreSpec(
        path: record.keystorePath,
        storePassword: storePassword ?? '',
        alias: keyAlias ?? '',
        keyPassword: keyPassword ?? storePassword ?? '',
      );
    }
    record.persist();
    _builds[id] = record;
    _queue.add(id);
    _pump();
    return record;
  }

  BuildRecord? get(String id) => _builds[id];

  List<BuildRecord> list() => _builds.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int? queuePosition(String id) {
    final i = _queue.indexOf(id);
    return i < 0 ? null : i + 1;
  }

  /// Deletes a finished or queued build. Running builds cannot be deleted.
  bool delete(String id) {
    final record = _builds[id];
    if (record == null || record.state == BuildState.running) return false;
    _queue.remove(id);
    _keystores.remove(id);
    _builds.remove(id);
    deleteQuietly(record.dir);
    return true;
  }

  void _pump() {
    while (_running < config.maxParallelBuilds && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      final record = _builds[id];
      if (record == null) continue;
      _running++;
      unawaited(_execute(record).whenComplete(() {
        _running--;
        _pump();
      }));
    }
  }

  Future<void> _execute(BuildRecord record) async {
    record
      ..state = BuildState.running
      ..startedAt = DateTime.now()
      ..persist();
    final keystore = _keystores.remove(record.id);
    try {
      final outcome = await pipeline.run(
        BuildRequest(zipPath: record.zipPath, workDir: record.dir, options: record.options, keystore: keystore),
        record.log,
        onStage: (stage) {
          record
            ..stage = stage
            ..persist();
        },
        onAnalysis: (analysis) {
          record
            ..kind = analysis.kind
            ..analysis = analysis.toJson()
            ..persist();
        },
      );
      record
        ..state = BuildState.succeeded
        ..apkPath = outcome.apkPath
        ..result = outcome.toJson();
    } on BuildFailure catch (e) {
      record
        ..state = BuildState.failed
        ..error = e.message;
      record.log.add('✖ ${e.message}');
    } catch (e, st) {
      record
        ..state = BuildState.failed
        ..error = 'Внутренняя ошибка движка: $e';
      record.log
        ..add('✖ Внутренняя ошибка: $e')
        ..add(st.toString());
    } finally {
      record.finishedAt = DateTime.now();
      record.persist();
      await record.log.close();
      deleteQuietly(record.keystorePath);
      deleteQuietly(record.zipPath);
    }
  }

  void _removeExpired() {
    final limit = DateTime.now().subtract(config.retention);
    for (final record in _builds.values.toList()) {
      final finished = record.finishedAt;
      if (finished != null && finished.isBefore(limit)) delete(record.id);
    }
  }

  static void _move(File from, String to) {
    try {
      from.renameSync(to);
    } on FileSystemException {
      from.copySync(to);
      from.deleteSync();
    }
  }
}
