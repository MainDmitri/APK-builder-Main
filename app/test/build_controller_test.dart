import 'dart:convert';
import 'dart:typed_data';

import 'package:appbuilder/services/backend/build_backend.dart';
import 'package:appbuilder/services/file_service.dart';
import 'package:appbuilder/state/build_controller.dart';
import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory backend that walks a build through its states.
class _ScriptedBackend implements BuildBackend {
  BuildSubmission? submitted;
  int calls = 0;

  @override
  BackendMode get mode => BackendMode.engine;

  @override
  bool get supportsKeystoreUpload => true;

  @override
  Duration get pollInterval => const Duration(milliseconds: 5);

  @override
  Future<BackendInfo> checkConnection() async => const BackendInfo(ok: true, message: 'ok');

  @override
  Future<KeystoreValidation> validateKeystore(KeystoreInput keystore) async =>
      KeystoreValidation(valid: keystore.storePassword == 'secret1', error: 'bad');

  @override
  Future<String> submit(BuildSubmission submission) async {
    submitted = submission;
    return 'b1';
  }

  @override
  Future<RemoteBuildStatus> status(String id, {int logFrom = 0}) async {
    calls++;
    if (calls < 3) {
      return RemoteBuildStatus(
        state: RemoteBuildState.running,
        stageTitle: 'Gradle',
        stages: const ['A', 'B'],
        currentStage: 1,
        logLines: ['line $calls'],
        nextLogIndex: logFrom + 1,
      );
    }
    return RemoteBuildStatus(
      state: RemoteBuildState.succeeded,
      apkFileName: 'Notes-1.0.0.apk',
      apkSize: 3,
      nextLogIndex: logFrom,
    );
  }

  @override
  Future<DownloadedApk> downloadApk(String id) async => DownloadedApk(Uint8List.fromList([1, 2, 3]), 'Notes-1.0.0.apk');

  @override
  Future<List<RemoteBuildSummary>> history() async => const [];

  @override
  void close() {}
}

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  files.forEach((k, v) => archive.addFile(ArchiveFile.bytes(k, utf8.encode(v))));
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('build lifecycle: submit, poll, finish', () async {
    final bytes = _zip({
      'index.html': '<html></html>',
      'appbuilder.json': '{"appName":"Notes","packageName":"com.example.notes","orientation":"portrait"}',
    });
    final c = BuildController()
      ..project = PickedFile('notes.zip', bytes)
      ..analysis = const ProjectAnalyzer().analyze(ZipMemorySource.fromBytes(bytes));
    c.appName.text = 'Notes';
    c.packageName.text = 'com.example.notes';
    final backend = _ScriptedBackend();
    expect(c.readinessErrors(backend), isEmpty);

    await c.startBuild(backend);
    expect(c.buildId, 'b1');
    expect(backend.submitted!.options.packageName, 'com.example.notes');
    expect(backend.submitted!.options.signing, SigningMode.debug);

    for (var i = 0; i < 100 && !(c.status?.isFinished ?? false); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(c.status!.state, RemoteBuildState.succeeded);
    expect(c.log, containsAll(['line 1', 'line 2']));
    expect(c.buildRunning, isFalse);
    c.dispose();
  });

  test('production keystore requires file and passwords', () {
    final c = BuildController()
      ..project = PickedFile('x.zip', _zip({'index.html': ''}))
      ..signing = SigningMode.keystore;
    final errors = c.readinessErrors(_ScriptedBackend());
    expect(errors.any((e) => e.contains('keystore')), isTrue);
    c.dispose();
  });
}
