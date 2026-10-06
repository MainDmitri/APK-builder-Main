import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../build_log.dart';
import '../config.dart';
import '../doctor.dart';
import '../pipeline/signer.dart';
import 'build_manager.dart';
import 'multipart.dart';

/// HTTP API of the AppBuilder Engine.
class EngineServer {
  EngineServer(this.config, this.builds);

  final EngineConfig config;
  final BuildManager builds;
  List<ToolStatus> _tools = const [];
  HttpServer? _server;

  String get _tmpDir => p.join(config.dataDir, 'tmp');

  Future<HttpServer> start() async {
    Directory(_tmpDir).createSync(recursive: true);
    _tools = await EngineDoctor(config).check();
    builds.start();
    final handler = const Pipeline()
        .addMiddleware(_cors)
        .addMiddleware(_errors)
        .addMiddleware(_auth)
        .addHandler(_route);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, config.port);
    _server!.autoCompress = true;
    return _server!;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    await builds.dispose();
  }

  // ----------------------------------------------------------- middleware

  static const _corsHeaders = {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
    'access-control-allow-headers': 'Authorization, Content-Type',
    'access-control-expose-headers': 'Content-Disposition, Content-Length',
    'access-control-max-age': '86400',
  };

  Handler _cors(Handler inner) => (request) async {
        if (request.method == 'OPTIONS') return Response(204, headers: _corsHeaders);
        final response = await inner(request);
        return response.change(headers: _corsHeaders);
      };

  Handler _errors(Handler inner) => (request) async {
        try {
          return await inner(request);
        } on HttpError catch (e) {
          return _json({'error': e.message}, status: e.status);
        } on FormatException catch (e) {
          return _json({'error': e.message}, status: 400);
        }
      };

  Handler _auth(Handler inner) => (request) {
        final token = config.token;
        if (token == null || !request.url.path.startsWith('api/')) return inner(request);
        final header = request.headers['authorization'] ?? '';
        final provided = header.startsWith('Bearer ') ? header.substring(7).trim() : '';
        if (!_constantTimeEquals(provided, token)) {
          return _json({'error': 'Нужен заголовок Authorization: Bearer <ENGINE_TOKEN>.'}, status: 401);
        }
        return inner(request);
      };

  static bool _constantTimeEquals(String a, String b) {
    final da = sha256.convert(utf8.encode(a)).bytes;
    final db = sha256.convert(utf8.encode(b)).bytes;
    var diff = 0;
    for (var i = 0; i < da.length; i++) {
      diff |= da[i] ^ db[i];
    }
    return diff == 0;
  }

  // --------------------------------------------------------------- routes

  FutureOr<Response> _route(Request request) {
    final segments = request.url.pathSegments.where((s) => s.isNotEmpty).toList();
    final method = request.method;
    final path = segments.join('/');

    if (method == 'GET' && segments.isEmpty) return _index();
    if (method == 'GET' && path == 'health') return _health();
    if (method == 'GET' && path == 'docs/agent-contract.md') {
      return Response.ok(buildAgentContract(), headers: {'content-type': 'text/markdown; charset=utf-8'});
    }
    if (segments.isNotEmpty && segments.first == 'api') {
      if (method == 'POST' && path == 'api/analyze') return _analyze(request);
      if (method == 'POST' && path == 'api/keystore/validate') return _validateKeystore(request);
      if (method == 'POST' && path == 'api/builds') return _createBuild(request);
      if (method == 'GET' && path == 'api/builds') return _listBuilds();
      if (segments.length >= 3 && segments[1] == 'builds') {
        final record = builds.get(segments[2]);
        if (record == null) return _json({'error': 'Сборка не найдена.'}, status: 404);
        if (segments.length == 3 && method == 'GET') return _buildStatus(request, record);
        if (segments.length == 3 && method == 'DELETE') return _deleteBuild(record);
        if (segments.length == 4 && method == 'GET' && segments[3] == 'apk') return _downloadApk(record);
        if (segments.length == 4 && method == 'GET' && segments[3] == 'log') return _downloadLog(record);
      }
    }
    return _json({'error': 'Не найдено: $method /$path'}, status: 404);
  }

  Response _index() => _json({
        'name': 'AppBuilder Engine',
        'contract': '/docs/agent-contract.md',
        'health': '/health',
        'api': [
          'POST /api/analyze',
          'POST /api/keystore/validate',
          'POST /api/builds',
          'GET /api/builds',
          'GET /api/builds/{id}?logFrom=N',
          'GET /api/builds/{id}/apk',
          'GET /api/builds/{id}/log',
          'DELETE /api/builds/{id}',
        ],
      });

  Response _health() {
    final missing = _tools.where((t) => t.required && !t.ok).map((t) => t.name).toList();
    return _json({
      'status': missing.isEmpty ? 'ok' : 'degraded',
      if (missing.isNotEmpty) 'missing': missing,
      'authRequired': config.token != null,
      'toolchain': EngineDoctor.toolchainJson(),
      'tools': _tools.map((t) => t.toJson()).toList(),
      'queue': {'running': builds.running, 'queued': builds.queued},
      'maxUploadMb': config.maxUploadBytes ~/ (1024 * 1024),
    });
  }

  Future<Response> _analyze(Request request) async {
    final form = await readMultipart(request, tempDir: _tmpDir, maxBytes: config.maxUploadBytes);
    try {
      final upload = form.files['project'];
      if (upload == null) throw HttpError(400, 'Нужен файл в поле «project».');
      final source = ZipMemorySource.fromBytes(await upload.file.readAsBytes());
      final analysis = const ProjectAnalyzer().analyze(source);
      final options = _parseOptions(form.fields['options']);
      return _json({
        'analysis': analysis.toJson(),
        if (analysis.kind != ProjectKind.unsupported) 'resolved': ResolvedAppConfig.resolve(analysis, options).toJson(),
      });
    } finally {
      form.cleanup();
    }
  }

  Future<Response> _validateKeystore(Request request) async {
    final form = await readMultipart(request, tempDir: _tmpDir, maxBytes: 10 * 1024 * 1024);
    final log = BuildLog(File(p.join(_tmpDir, 'keystore-${DateTime.now().microsecondsSinceEpoch}.log')));
    try {
      final upload = form.files['keystore'];
      if (upload == null) throw HttpError(400, 'Нужен файл в поле «keystore».');
      final spec = _keystoreSpec(upload.file.path, form.fields);
      final check = await ApkSigner(config).validate(spec, log);
      return _json(check.toJson());
    } finally {
      await log.close();
      deleteFileQuietly(log.file);
      form.cleanup();
    }
  }

  Future<Response> _createBuild(Request request) async {
    final form = await readMultipart(request, tempDir: _tmpDir, maxBytes: config.maxUploadBytes);
    try {
      final project = form.files['project'];
      if (project == null) throw HttpError(400, 'Нужен ZIP-архив в поле «project».');
      final options = _parseOptions(form.fields['options']);
      final keystore = form.files['keystore'];
      KeystoreSpec? spec;
      if (options.signing == SigningMode.keystore) {
        if (keystore == null) throw HttpError(400, 'Для подписи Production Keystore загрузите файл в поле «keystore».');
        spec = _keystoreSpec(keystore.file.path, form.fields);
      } else if (options.signing == SigningMode.repoSecrets) {
        throw HttpError(400, 'Режим repo-secrets используется только GitHub-сборщиком.');
      }
      final record = builds.submit(
        uploadedZip: project.file,
        options: options,
        uploadedKeystore: spec == null ? null : keystore!.file,
        storePassword: spec?.storePassword,
        keyAlias: spec?.alias,
        keyPassword: spec?.keyPassword,
      );
      form.files.remove('project');
      if (options.signing == SigningMode.keystore) form.files.remove('keystore');
      return _json(record.toJson(), status: 202);
    } finally {
      form.cleanup();
    }
  }

  Response _listBuilds() => _json({
        'builds': builds.list().map((b) => b.toJson()).toList(),
      });

  Response _buildStatus(Request request, BuildRecord record) {
    final from = int.tryParse(request.url.queryParameters['logFrom'] ?? '') ?? 0;
    final json = record.toJson(logFrom: from);
    final position = builds.queuePosition(record.id);
    if (position != null) json['queuePosition'] = position;
    return _json(json);
  }

  Response _deleteBuild(BuildRecord record) {
    if (!builds.delete(record.id)) return _json({'error': 'Идёт сборка — удалить нельзя.'}, status: 409);
    return _json({'deleted': record.id});
  }

  Response _downloadApk(BuildRecord record) {
    final path = record.apkPath;
    if (record.state != BuildState.succeeded || path == null || !File(path).existsSync()) {
      return _json({'error': 'APK ещё не готов.'}, status: 404);
    }
    final file = File(path);
    return Response.ok(file.openRead(), headers: {
      'content-type': 'application/vnd.android.package-archive',
      'content-length': '${file.lengthSync()}',
      'content-disposition': _attachment(p.basename(path)),
    });
  }

  Response _downloadLog(BuildRecord record) {
    final file = record.log.file;
    if (!file.existsSync()) return _json({'error': 'Лог не найден.'}, status: 404);
    return Response.ok(file.openRead(), headers: {
      'content-type': 'text/plain; charset=utf-8',
      'content-disposition': _attachment('build-${record.id}.log'),
    });
  }

  // -------------------------------------------------------------- helpers

  static BuildOptions _parseOptions(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const BuildOptions();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw HttpError(400, 'Поле «options» должно быть JSON-объектом.');
    final options = BuildOptions.fromJson(decoded.cast<String, Object?>());
    final errors = [
      if (options.packageName != null) ?Validators.packageName(options.packageName),
      if (options.appName != null) ?Validators.appName(options.appName),
      if (options.versionName != null) ?Validators.versionName(options.versionName),
      if (options.versionCode != null) ?Validators.versionCode('${options.versionCode}'),
    ];
    if (errors.isNotEmpty) throw HttpError(400, errors.join('; '));
    return options;
  }

  static KeystoreSpec _keystoreSpec(String path, Map<String, String> fields) {
    final storePassword = fields['storePassword'] ?? '';
    final alias = fields['keyAlias'] ?? '';
    final keyPassword = (fields['keyPassword']?.isNotEmpty ?? false) ? fields['keyPassword']! : storePassword;
    final error = Validators.keystorePassword(storePassword) ?? Validators.keyAlias(alias);
    if (error != null) throw HttpError(400, error);
    final head = File(path).openSync();
    final bytes = head.readSync(4);
    head.closeSync();
    final formatError = Validators.keystoreBytes(bytes);
    if (formatError != null) throw HttpError(400, formatError);
    return KeystoreSpec(path: path, storePassword: storePassword, alias: alias, keyPassword: keyPassword);
  }

  static String _attachment(String fileName) {
    final ascii = fileName.replaceAll(RegExp(r'[^\x20-\x7E]'), '_').replaceAll('"', '');
    return 'attachment; filename="$ascii"; filename*=UTF-8\'\'${Uri.encodeComponent(fileName)}';
  }

  static Response _json(Object body, {int status = 200}) => Response(
        status,
        body: const JsonEncoder.withIndent('  ').convert(body),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

void deleteFileQuietly(File file) {
  try {
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // ignore
  }
}
