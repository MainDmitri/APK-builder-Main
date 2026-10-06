import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'build_backend.dart';

/// Client of a self-hosted AppBuilder Engine (engine/ in this repository).
class EngineBackend implements BuildBackend {
  EngineBackend({required String baseUrl, String? token, http.Client? client})
      : _base = Uri.parse(baseUrl.trim().replaceFirst(RegExp(r'/+$'), '')),
        _token = (token?.trim().isEmpty ?? true) ? null : token!.trim(),
        _client = client ?? http.Client();

  final Uri _base;
  final String? _token;
  final http.Client _client;

  static const _shortTimeout = Duration(seconds: 20);
  static const _uploadTimeout = Duration(minutes: 15);

  @override
  BackendMode get mode => BackendMode.engine;

  @override
  bool get supportsKeystoreUpload => true;

  @override
  Duration get pollInterval => const Duration(seconds: 2);

  Uri _uri(String path, [Map<String, String>? query]) =>
      _base.replace(path: '${_base.path}$path', queryParameters: query);

  Map<String, String> get _headers => {if (_token != null) 'Authorization': 'Bearer $_token'};

  Future<Map<String, dynamic>> _getJson(String path, [Map<String, String>? query]) async {
    final http.Response response;
    try {
      response = await _client.get(_uri(path, query), headers: _headers).timeout(_shortTimeout);
    } on TimeoutException {
      throw BackendException('Сервер ${_base.host} не отвечает.');
    } on http.ClientException catch (e) {
      throw BackendException('Нет соединения с ${_base.host}: ${e.message}');
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      body = null;
    }
    if (response.statusCode >= 400) {
      final message = body is Map && body['error'] is String ? body['error'] as String : 'HTTP ${response.statusCode}';
      if (response.statusCode == 401) throw BackendException('Неверный токен доступа: $message');
      throw BackendException(message);
    }
    if (body is! Map<String, dynamic>) throw BackendException('Сервер вернул не JSON (это точно AppBuilder Engine?).');
    return body;
  }

  Future<Map<String, dynamic>> _sendMultipart(http.MultipartRequest request, Duration timeout) async {
    request.headers.addAll(_headers);
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return _decode(await http.Response.fromStream(streamed).timeout(timeout));
    } on TimeoutException {
      throw BackendException('Превышено время ожидания ответа сервера.');
    } on http.ClientException catch (e) {
      throw BackendException('Ошибка соединения: ${e.message}');
    }
  }

  @override
  Future<BackendInfo> checkConnection() async {
    final health = await _getJson('/health');
    await _getJson('/api/builds'); // verifies the token
    final toolchain = (health['toolchain'] as Map?)?.cast<String, Object?>() ?? const {};
    final missing = (health['missing'] as List?)?.cast<String>() ?? const [];
    return BackendInfo(
      ok: health['status'] == 'ok',
      message: missing.isEmpty ? 'Движок готов к сборке' : 'Не хватает инструментов: ${missing.join(', ')}',
      details: {
        'AGP': '${toolchain['androidGradlePlugin']}',
        'Gradle': '${toolchain['gradle']}',
        'compileSdk': '${toolchain['compileSdk']}',
        'Node.js': '${toolchain['node']}',
        'Контракт': 'v${toolchain['contractVersion']}',
        'Очередь': '${(health['queue'] as Map?)?['running'] ?? 0} / ${(health['queue'] as Map?)?['queued'] ?? 0}',
      },
    );
  }

  @override
  Future<KeystoreValidation> validateKeystore(KeystoreInput keystore) async {
    final request = http.MultipartRequest('POST', _uri('/api/keystore/validate'))
      ..fields.addAll({
        'storePassword': keystore.storePassword,
        'keyAlias': keystore.alias,
        'keyPassword': keystore.keyPassword,
      })
      ..files.add(http.MultipartFile.fromBytes('keystore', keystore.bytes, filename: keystore.fileName));
    final json = await _sendMultipart(request, const Duration(minutes: 2));
    return KeystoreValidation(
      valid: json['valid'] == true,
      error: json['error'] as String?,
      aliases: (json['aliases'] as List?)?.cast<String>() ?? const [],
      owner: json['owner'] as String?,
      sha256: json['sha256'] as String?,
      validUntil: json['validUntil'] as String?,
    );
  }

  @override
  Future<String> submit(BuildSubmission submission) async {
    final request = http.MultipartRequest('POST', _uri('/api/builds'))
      ..fields['options'] = jsonEncode(submission.options.toJson())
      ..files.add(http.MultipartFile.fromBytes('project', submission.projectZip, filename: submission.projectFileName));
    final icon = submission.icon;
    if (icon != null) {
      request.files.add(http.MultipartFile.fromBytes('icon', icon, filename: submission.iconUploadName));
    }
    final ks = submission.keystore;
    if (ks != null) {
      request
        ..fields.addAll({'storePassword': ks.storePassword, 'keyAlias': ks.alias, 'keyPassword': ks.keyPassword})
        ..files.add(http.MultipartFile.fromBytes('keystore', ks.bytes, filename: ks.fileName));
    }
    final json = await _sendMultipart(request, _uploadTimeout);
    final id = json['id'];
    if (id is! String) throw BackendException('Сервер не вернул id сборки.');
    return id;
  }

  @override
  Future<RemoteBuildStatus> status(String id, {int logFrom = 0}) async {
    final json = await _getJson('/api/builds/$id', {'logFrom': '$logFrom'});
    final stages = ((json['stages'] as List?) ?? const []).map((s) => (s as Map)['title'] as String).toList();
    final stageIds = ((json['stages'] as List?) ?? const []).map((s) => (s as Map)['id'] as String).toList();
    final stageIndex = stageIds.indexOf(json['stage'] as String? ?? '');
    final log = (json['log'] as Map?) ?? const {};
    final result = (json['result'] as Map?) ?? const {};
    final analysis = (json['analysis'] as Map?) ?? const {};
    return RemoteBuildStatus(
      state: RemoteBuildState.values.byName(json['state'] as String),
      stageTitle: json['stageTitle'] as String?,
      stages: stages,
      currentStage: stageIndex < 0 ? null : stageIndex,
      logLines: ((log['lines'] as List?) ?? const []).cast<String>(),
      nextLogIndex: (log['next'] as int?) ?? logFrom,
      error: json['error'] as String?,
      apkFileName: result['fileName'] as String?,
      apkSize: result['size'] as int?,
      apkSha256: result['sha256'] as String?,
      signingSchemes: ((result['signingSchemes'] as List?) ?? const []).cast<String>(),
      warnings: ((analysis['warnings'] as List?) ?? const []).cast<String>(),
      queuePosition: json['queuePosition'] as int?,
    );
  }

  @override
  Future<ApkSource> apkSource(String id) async {
    final status = await this.status(id, logFrom: 1 << 30);
    if (status.state != RemoteBuildState.succeeded) throw BackendException('Сборка $id не завершилась успешно.');
    return ApkSource(
      url: _uri('/api/builds/$id/apk'),
      fileName: status.apkFileName ?? 'app.apk',
      headers: _headers,
      size: status.apkSize,
    );
  }

  @override
  Future<List<RemoteBuildSummary>> history() async {
    final json = await _getJson('/api/builds');
    return ((json['builds'] as List?) ?? const []).map((raw) {
      final b = raw as Map;
      final result = (b['result'] as Map?) ?? const {};
      final app = (result['app'] as Map?) ?? const {};
      final options = (b['options'] as Map?) ?? const {};
      return RemoteBuildSummary(
        id: b['id'] as String,
        state: RemoteBuildState.values.byName(b['state'] as String),
        title: (app['appName'] ?? options['appName'] ?? b['id']) as String,
        createdAt: DateTime.parse(b['createdAt'] as String).toLocal(),
        apkFileName: result['fileName'] as String?,
      );
    }).toList();
  }

  @override
  void close() => _client.close();
}
