import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../backend/build_backend.dart';
import 'install_messages.dart';
import 'transfer_models.dart';

/// Browser: the APK is downloaded into memory and then saved as a file.
/// Installing is possible only in the Android version of AppBuilder.
class ApkStore {
  ApkStore({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, Uint8List> _files = {};

  bool get canInstall => false;

  Stream<TransferUpdate> download(ApkSource source, String buildId) async* {
    final cached = _files[buildId];
    if (cached != null) {
      yield TransferUpdate(TransferPhase.done, received: cached.length, total: cached.length);
      return;
    }
    yield TransferUpdate(TransferPhase.queued, total: source.size);
    final http.StreamedResponse response;
    try {
      response = await _client.send(http.Request('GET', source.url)..headers.addAll(source.headers));
    } on http.ClientException catch (e) {
      yield TransferUpdate(TransferPhase.failed, message: 'Нет соединения: ${e.message}');
      return;
    }
    if (response.statusCode != 200) {
      yield TransferUpdate(TransferPhase.failed, message: TransferMessages.downloadFailure(response.statusCode));
      return;
    }
    final total = response.contentLength ?? source.size;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
      yield TransferUpdate(TransferPhase.downloading, received: builder.length, total: total);
    }
    final bytes = builder.takeBytes();
    _files[buildId] = bytes;
    yield TransferUpdate(TransferPhase.done, received: bytes.length, total: bytes.length);
  }

  Future<void> cancel(String buildId) async {}

  Future<Uint8List> read(String buildId, String? path) async => _files[buildId]!;

  Future<bool> installAllowed() async => false;

  Future<void> openInstallSettings() async {}

  Future<bool> launch(String packageName) async => false;

  Stream<InstallUpdate> install(String path) =>
      Stream.value(const InstallUpdate(InstallPhase.failed, message: 'Установка доступна только в Android-версии AppBuilder.'));
}
