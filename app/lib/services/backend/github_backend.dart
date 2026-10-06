import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'build_backend.dart';

/// Serverless backend: commits `inbox/<id>/project.zip` + `request.json` to
/// the user's repository; the "Inbox build" workflow builds the APK and
/// publishes it as the pre-release `build-<id>`.
///
/// Needs a token with Contents: read/write and Actions: read
/// (fine-grained PAT) or the `repo` + `workflow` scopes (classic PAT).
class GitHubBackend implements BuildBackend {
  GitHubBackend({
    required this.owner,
    required this.repo,
    required String token,
    this.branch,
    http.Client? client,
  })  : _token = token.trim(),
        _client = client ?? http.Client();

  final String owner;
  final String repo;

  /// Target branch; null → repository default branch.
  final String? branch;
  final String _token;
  final http.Client _client;
  final Map<String, String> _commitByBuild = {};
  String? _defaultBranch;

  static const workflowFile = 'inbox-build.yml';
  static const _api = 'https://api.github.com';
  static const _maxZipBytes = 75 * 1024 * 1024;

  @override
  BackendMode get mode => BackendMode.github;

  @override
  bool get supportsKeystoreUpload => false;

  @override
  Duration get pollInterval => const Duration(seconds: 10);

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $_token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  String get _repoPath => '/repos/$owner/$repo';

  Future<http.Response> _request(String method, String path, {Object? body, Map<String, String>? query}) async {
    final uri = Uri.parse('$_api$path').replace(queryParameters: query);
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) {
      request
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    try {
      return await http.Response.fromStream(await _client.send(request).timeout(const Duration(minutes: 5)));
    } on TimeoutException {
      throw BackendException('GitHub не отвечает.');
    } on http.ClientException catch (e) {
      throw BackendException('Нет соединения с GitHub: ${e.message}');
    }
  }

  Future<Map<String, dynamic>> _json(String method, String path, {Object? body, Map<String, String>? query}) async {
    final response = await _request(method, path, body: body, query: query);
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map ? decoded['message'] : null;
      throw BackendException(switch (response.statusCode) {
        401 => 'GitHub: неверный или просроченный токен.',
        403 => 'GitHub: недостаточно прав у токена ($message).',
        404 => 'GitHub: не найдено ($path). Проверьте владельца, репозиторий и права токена.',
        _ => 'GitHub ${response.statusCode}: $message',
      });
    }
    return decoded is Map<String, dynamic> ? decoded : {'items': decoded};
  }

  Future<String> _branch() async {
    if (branch != null && branch!.trim().isNotEmpty) return branch!.trim();
    _defaultBranch ??= (await _json('GET', _repoPath))['default_branch'] as String;
    return _defaultBranch!;
  }

  @override
  Future<BackendInfo> checkConnection() async {
    final repoInfo = await _json('GET', _repoPath);
    final permissions = (repoInfo['permissions'] as Map?) ?? const {};
    if (permissions['push'] != true) {
      return const BackendInfo(ok: false, message: 'У токена нет права записи в репозиторий (Contents: write).');
    }
    _defaultBranch = repoInfo['default_branch'] as String;
    final target = await _branch();
    final workflow = await _request('GET', '$_repoPath/contents/.github/workflows/$workflowFile', query: {'ref': target});
    if (workflow.statusCode == 404) {
      return BackendInfo(
        ok: false,
        message: 'В ветке «$target» нет .github/workflows/$workflowFile. Слейте ветку с AppBuilder в «$target» '
            'или укажите в настройках ветку, где этот workflow есть.',
      );
    }
    return BackendInfo(
      ok: true,
      message: 'Репозиторий готов: сборка в GitHub Actions',
      details: {
        'Репозиторий': '$owner/$repo',
        'Ветка': target,
        'Приватный': repoInfo['private'] == true ? 'да' : 'нет',
      },
    );
  }

  @override
  Future<KeystoreValidation> validateKeystore(KeystoreInput keystore) =>
      throw BackendException('В режиме GitHub ключ берётся из секретов репозитория — загрузка keystore не используется.');

  static String _newId() {
    final random = Random.secure();
    final ts = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').substring(0, 14);
    final rnd = List.generate(3, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return '$ts-$rnd';
  }

  @override
  Future<String> submit(BuildSubmission submission) async {
    if (submission.projectZip.length > _maxZipBytes) {
      throw BackendException('Архив больше ${_maxZipBytes ~/ (1024 * 1024)} МБ — GitHub API его не примет.');
    }
    final id = _newId();
    final target = await _branch();
    final icon = submission.icon;
    final request = utf8.encode(const JsonEncoder.withIndent('  ').convert({
      'id': id,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'projectFileName': submission.projectFileName,
      'options': submission.options.toJson(),
      if (icon != null) 'icon': submission.iconUploadName,
    }));
    final zipBlob = await _createBlob(submission.projectZip);
    final iconBlob = icon == null ? null : await _createBlob(icon);
    final requestBlob = await _createBlob(Uint8List.fromList(request));

    // Commit both files atomically on top of the branch head (retry on races).
    for (var attempt = 0; attempt < 3; attempt++) {
      final ref = await _json('GET', '$_repoPath/git/ref/heads/$target');
      final headSha = (ref['object'] as Map)['sha'] as String;
      final head = await _json('GET', '$_repoPath/git/commits/$headSha');
      final tree = await _json('POST', '$_repoPath/git/trees', body: {
        'base_tree': (head['tree'] as Map)['sha'],
        'tree': [
          {'path': 'inbox/$id/project.zip', 'mode': '100644', 'type': 'blob', 'sha': zipBlob},
          if (iconBlob != null)
            {'path': 'inbox/$id/${submission.iconUploadName}', 'mode': '100644', 'type': 'blob', 'sha': iconBlob},
          {'path': 'inbox/$id/request.json', 'mode': '100644', 'type': 'blob', 'sha': requestBlob},
        ],
      });
      final commit = await _json('POST', '$_repoPath/git/commits', body: {
        'message': 'AppBuilder: build request $id',
        'tree': tree['sha'],
        'parents': [headSha],
      });
      final update = await _request('PATCH', '$_repoPath/git/refs/heads/$target', body: {'sha': commit['sha']});
      if (update.statusCode == 200) {
        _commitByBuild[id] = commit['sha'] as String;
        return id;
      }
      if (update.statusCode != 422) {
        throw BackendException('GitHub: не удалось обновить ветку $target (${update.statusCode}).');
      }
    }
    throw BackendException('Ветка $target постоянно меняется — повторите отправку.');
  }

  Future<String> _createBlob(Uint8List bytes) async {
    final blob = await _json('POST', '$_repoPath/git/blobs', body: {
      'content': base64Encode(bytes),
      'encoding': 'base64',
    });
    return blob['sha'] as String;
  }

  Future<Map<String, dynamic>?> _release(String id) async {
    final response = await _request('GET', '$_repoPath/releases/tags/build-$id');
    if (response.statusCode == 404) return null;
    if (response.statusCode >= 400) await _json('GET', '$_repoPath/releases/tags/build-$id');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Release assets are served through a redirect to a storage host that
  /// must be requested without the GitHub token.
  Future<Uint8List> _downloadAsset(int assetId) async {
    final request = http.Request('GET', Uri.parse('$_api$_repoPath/releases/assets/$assetId'))
      ..headers.addAll({..._headers, 'Accept': 'application/octet-stream'})
      ..followRedirects = false;
    final first = await http.Response.fromStream(await _client.send(request).timeout(const Duration(minutes: 5)));
    if (first.statusCode == 200) return first.bodyBytes;
    final location = first.headers['location'];
    if (first.statusCode >= 300 && first.statusCode < 400 && location != null) {
      final second = await _client.get(Uri.parse(location)).timeout(const Duration(minutes: 10));
      if (second.statusCode == 200) return second.bodyBytes;
      throw BackendException('Не удалось скачать файл релиза (${second.statusCode}).');
    }
    throw BackendException('Не удалось скачать файл релиза (${first.statusCode}).');
  }

  Map<String, dynamic>? _asset(Map<String, dynamic> release, bool Function(String name) test) {
    for (final a in (release['assets'] as List? ?? const [])) {
      final asset = a as Map<String, dynamic>;
      if (test(asset['name'] as String)) return asset;
    }
    return null;
  }

  Future<String?> _commitFor(String id) async {
    final cached = _commitByBuild[id];
    if (cached != null) return cached;
    final commits = await _json('GET', '$_repoPath/commits', query: {
      'path': 'inbox/$id/request.json',
      'sha': await _branch(),
      'per_page': '1',
    });
    final items = commits['items'] as List? ?? const [];
    if (items.isEmpty) return null;
    return _commitByBuild[id] = (items.first as Map)['sha'] as String;
  }

  @override
  Future<RemoteBuildStatus> status(String id, {int logFrom = 0}) async {
    final release = await _release(id);
    if (release != null) {
      final resultAsset = _asset(release, (n) => n == 'result.json');
      final logAsset = _asset(release, (n) => n == 'build.log');
      final result = resultAsset == null
          ? const <String, dynamic>{}
          : jsonDecode(utf8.decode(await _downloadAsset(resultAsset['id'] as int))) as Map<String, dynamic>;
      final logLines = logAsset == null
          ? const <String>[]
          : const LineSplitter().convert(utf8.decode(await _downloadAsset(logAsset['id'] as int), allowMalformed: true));
      final success = result['success'] == true;
      final apk = _asset(release, (n) => n.endsWith('.apk'));
      return RemoteBuildStatus(
        state: success ? RemoteBuildState.succeeded : RemoteBuildState.failed,
        stageTitle: success ? 'Готово' : 'Ошибка',
        logLines: logFrom < logLines.length ? logLines.sublist(logFrom) : const [],
        nextLogIndex: logLines.length,
        error: success ? null : (result['error'] as String? ?? 'Сборка завершилась ошибкой'),
        apkFileName: apk?['name'] as String?,
        apkSize: apk?['size'] as int?,
        apkSha256: result['sha256'] as String?,
        signingSchemes: ((result['signingSchemes'] as List?) ?? const []).cast<String>(),
        warnings: ((((result['analysis'] as Map?) ?? const {})['warnings'] as List?) ?? const []).cast<String>(),
        detailsUrl: release['html_url'] as String?,
      );
    }

    final commit = await _commitFor(id);
    if (commit == null) {
      return RemoteBuildStatus(state: RemoteBuildState.failed, error: 'Запрос сборки $id не найден в репозитории.', nextLogIndex: logFrom);
    }
    final runs = await _json('GET', '$_repoPath/actions/workflows/$workflowFile/runs', query: {'head_sha': commit});
    final list = (runs['workflow_runs'] as List?) ?? const [];
    if (list.isEmpty) {
      return RemoteBuildStatus(
        state: RemoteBuildState.queued,
        stageTitle: 'Ожидание запуска workflow в GitHub Actions',
        nextLogIndex: logFrom,
      );
    }
    final run = list.first as Map<String, dynamic>;
    final status = run['status'] as String?;
    final conclusion = run['conclusion'] as String?;
    if (status == 'completed' && conclusion != 'success') {
      return RemoteBuildStatus(
        state: RemoteBuildState.failed,
        error: 'Workflow «Inbox build» завершился: $conclusion. Подробности — на странице запуска.',
        detailsUrl: run['html_url'] as String?,
        nextLogIndex: logFrom,
      );
    }
    return RemoteBuildStatus(
      state: status == 'queued' || status == 'waiting' || status == 'pending' ? RemoteBuildState.queued : RemoteBuildState.running,
      stageTitle: status == 'completed' ? 'Публикация результата' : 'GitHub Actions: $status',
      detailsUrl: run['html_url'] as String?,
      nextLogIndex: logFrom,
    );
  }

  @override
  Future<ApkSource> apkSource(String id) async {
    final release = await _release(id);
    if (release == null) throw BackendException('Релиз build-$id ещё не опубликован.');
    final apk = _asset(release, (n) => n.endsWith('.apk'));
    if (apk == null) throw BackendException('В релизе build-$id нет APK.');
    final assetUrl = Uri.parse('$_api$_repoPath/releases/assets/${apk['id']}');
    final assetHeaders = {..._headers, 'Accept': 'application/octet-stream'};
    final fileName = apk['name'] as String;
    final size = apk['size'] as int?;

    // The API answers with a redirect to a short-lived signed address of the
    // file storage: the download itself then needs no token.
    final request = http.Request('GET', assetUrl)
      ..headers.addAll(assetHeaders)
      ..followRedirects = false;
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw BackendException('GitHub не отвечает.');
    } on http.ClientException catch (e) {
      throw BackendException('Нет соединения с GitHub: ${e.message}');
    }
    final location = response.headers['location'];
    await response.stream.listen(null).cancel();
    if (response.statusCode >= 300 && response.statusCode < 400 && location != null) {
      return ApkSource(url: Uri.parse(location), fileName: fileName, size: size);
    }
    if (response.statusCode == 200) {
      return ApkSource(url: assetUrl, fileName: fileName, headers: assetHeaders, size: size);
    }
    throw BackendException('Не удалось получить ссылку на APK (${response.statusCode}).');
  }

  @override
  Future<List<RemoteBuildSummary>> history() async {
    final json = await _json('GET', '$_repoPath/releases', query: {'per_page': '50'});
    final releases = (json['items'] as List?) ?? const [];
    return releases
        .cast<Map<String, dynamic>>()
        .where((r) => (r['tag_name'] as String).startsWith('build-'))
        .map((r) {
      final apk = _asset(r, (n) => n.endsWith('.apk'));
      final name = (r['name'] as String?) ?? r['tag_name'] as String;
      return RemoteBuildSummary(
        id: (r['tag_name'] as String).substring('build-'.length),
        state: apk != null ? RemoteBuildState.succeeded : RemoteBuildState.failed,
        title: name,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        apkFileName: apk?['name'] as String?,
        detailsUrl: r['html_url'] as String?,
      );
    }).toList();
  }

  @override
  void close() => _client.close();
}
