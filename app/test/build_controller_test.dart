import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appbuilder/services/backend/build_backend.dart';
import 'package:appbuilder/services/file_service.dart';
import 'package:appbuilder/services/transfer/apk_store.dart';
import 'package:appbuilder/services/transfer/transfer_models.dart';
import 'package:appbuilder/state/build_controller.dart';
import 'package:appbuilder/state/downloads_controller.dart';
import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory backend that walks a build through its states and serves the
/// APK from a local HTTP server.
class _ScriptedBackend implements BuildBackend {
  _ScriptedBackend(this.apkUrl, this.apkSize);

  final Uri apkUrl;
  final int apkSize;
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
      apkSize: apkSize,
      nextLogIndex: logFrom,
    );
  }

  @override
  Future<ApkSource> apkSource(String id) async =>
      ApkSource(url: apkUrl, fileName: 'Notes-1.0.0.apk', size: apkSize, headers: const {'Authorization': 'Bearer t'});

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

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late Directory storage;
  final apk = Uint8List.fromList(List.generate(300 * 1024, (i) => i % 251));
  final requests = <HttpRequest>[];

  setUp(() async {
    // flutter_test answers every HTTP request with 400; these tests use a real local server.
    HttpOverrides.global = null;
    requests.clear();
    storage = await Directory.systemTemp.createTemp('appbuilder-store');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request);
      if (request.uri.path == '/missing.apk') {
        request.response.statusCode = 404;
      } else {
        request.response
          ..headers.contentLength = apk.length
          ..add(apk);
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await storage.delete(recursive: true);
  });

  Uri url(String path) => Uri.parse('http://${server.address.host}:${server.port}$path');
  ApkStore store() => ApkStore(storageDir: () async => storage);

  test('build lifecycle: submit, poll, finish and download the APK automatically', () async {
    final bytes = _zip({
      'index.html': '<html></html>',
      'appbuilder.json': '{"appName":"Notes","packageName":"com.example.notes","orientation":"portrait"}',
    });
    final downloads = DownloadsController(store: store());
    final c = BuildController(downloads: downloads)
      ..project = PickedFile('notes.zip', bytes)
      ..analysis = const ProjectAnalyzer().analyze(ZipMemorySource.fromBytes(bytes))
      ..icon = PickedFile('logo.webp', Uint8List.fromList([1, 2, 3]));
    c.appName.text = 'Notes';
    c.packageName.text = 'com.example.notes';
    final backend = _ScriptedBackend(url('/app.apk'), apk.length);
    expect(c.readinessErrors(backend), isEmpty);

    await c.startBuild(backend);
    expect(c.buildId, 'b1');
    expect(backend.submitted!.options.packageName, 'com.example.notes');
    expect(backend.submitted!.options.signing, SigningMode.debug);
    expect(backend.submitted!.icon, [1, 2, 3]);
    expect(backend.submitted!.iconUploadName, 'icon.webp');

    await _until(() => c.status?.isFinished ?? false);
    expect(c.status!.state, RemoteBuildState.succeeded);
    expect(c.log, containsAll(['line 1', 'line 2']));
    expect(c.buildRunning, isFalse);
    expect(c.finishedAt, isNotNull);

    await _until(() => downloads.job('b1')?.downloaded ?? false);
    final job = downloads.job('b1')!;
    expect(job.fraction, 1);
    expect(File(job.path!).readAsBytesSync(), apk);
    expect(requests.single.headers.value('authorization'), 'Bearer t');
    c.dispose();
    downloads.dispose();
  });

  test('downloaded APK is reused instead of downloading again', () async {
    final first = store();
    final source = ApkSource(url: url('/app.apk'), fileName: 'A.apk', size: apk.length);
    final updates = await first.download(source, 'x1').toList();
    expect(updates.first.phase, TransferPhase.queued);
    expect(updates.last.phase, TransferPhase.done);
    expect(requests, hasLength(1));

    final again = await store().download(source, 'x1').toList();
    expect(again.single.phase, TransferPhase.done);
    expect(again.single.path, updates.last.path);
    expect(requests, hasLength(1));
  });

  test('HTTP errors and truncated files are reported', () async {
    final missing = await store().download(ApkSource(url: url('/missing.apk'), fileName: 'M.apk'), 'x2').toList();
    expect(missing.last.phase, TransferPhase.failed);
    expect(missing.last.message, contains('404'));

    final wrongSize = await store()
        .download(ApkSource(url: url('/app.apk'), fileName: 'W.apk', size: apk.length + 1), 'x3')
        .toList();
    expect(wrongSize.last.phase, TransferPhase.failed);
    expect(File('${storage.path}/apk/x3/W.apk').existsSync(), isFalse);
  });

  test('icon pictures are checked by content', () {
    expect(BuildController.validateIcon(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0])), isNull);
    expect(BuildController.validateIcon(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), isNull);
    expect(
      BuildController.validateIcon(Uint8List.fromList(ascii.encode('RIFF\x00\x00\x00\x00WEBPVP8 '))),
      isNull,
    );
    expect(BuildController.validateIcon(Uint8List.fromList(ascii.encode('<svg></svg>'))), contains('PNG'));
    expect(BuildController.validateIcon(Uint8List(BuildController.maxIconBytes + 1)), contains('5 МБ'));
  });

  test('production keystore requires file and passwords', () {
    final c = BuildController()
      ..project = PickedFile('x.zip', _zip({'index.html': ''}))
      ..signing = SigningMode.keystore;
    final errors = c.readinessErrors(_ScriptedBackend(url('/app.apk'), 1));
    expect(errors.any((e) => e.contains('keystore')), isTrue);
    c.dispose();
  });
}
