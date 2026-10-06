import 'dart:convert';
import 'dart:io';

import 'package:appbuilder_engine/engine.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory tmp;
  late EngineServer server;
  late Uri base;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('engine-server');
    final config = testConfig(tmp.path, token: 'secret-token');
    server = EngineServer(config, BuildManager(config));
    final http = await server.start();
    base = Uri.parse('http://127.0.0.1:${http.port}');
  });

  tearDownAll(() async {
    await server.stop();
    await tmp.delete(recursive: true);
  });

  Map<String, String> auth() => {'Authorization': 'Bearer secret-token'};

  test('health and contract are public', () async {
    final health = await http.get(base.resolve('/health'));
    expect(health.statusCode, 200);
    final json = jsonDecode(health.body) as Map;
    expect(json['authRequired'], isTrue);
    expect(json['toolchain']['androidGradlePlugin'], isNotEmpty);

    final contract = await http.get(base.resolve('/docs/agent-contract.md'));
    expect(contract.statusCode, 200);
    expect(contract.headers['content-type'], contains('text/markdown'));
    expect(contract.body, contains('AI Agent Contract'));
    expect(contract.headers['access-control-allow-origin'], '*');
  });

  test('api requires the token', () async {
    final response = await http.get(base.resolve('/api/builds'));
    expect(response.statusCode, 401);
    final ok = await http.get(base.resolve('/api/builds'), headers: auth());
    expect(ok.statusCode, 200);
  });

  test('CORS preflight', () async {
    final request = http.Request('OPTIONS', base.resolve('/api/builds'));
    final response = await http.Client().send(request);
    expect(response.statusCode, 204);
    expect(response.headers['access-control-allow-headers'], contains('Authorization'));
  });

  test('analyze endpoint', () async {
    final zip = await zipSample('vite-react', tmp.path);
    final request = http.MultipartRequest('POST', base.resolve('/api/analyze'))
      ..headers.addAll(auth())
      ..files.add(await http.MultipartFile.fromPath('project', zip));
    final response = await http.Response.fromStream(await request.send());
    expect(response.statusCode, 200, reason: response.body);
    final json = jsonDecode(response.body) as Map;
    expect(json['analysis']['kind'], 'node');
    expect(json['analysis']['node']['framework'], 'vite');
    expect(json['resolved']['packageName'], 'net.appbuilder.samples.habits');
  });

  test('keystore validation endpoint', () async {
    final jks = p.join(tmp.path, 'srv.jks');
    await Process.run('keytool', [
      '-genkeypair', '-noprompt', '-keystore', jks, '-storetype', 'PKCS12', '-storepass', 'pkcs-pass', //
      '-alias', 'upload', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '30', '-dname', 'CN=Srv',
    ]);
    Future<Map> validate(String alias) async {
      final request = http.MultipartRequest('POST', base.resolve('/api/keystore/validate'))
        ..headers.addAll(auth())
        ..fields.addAll({'storePassword': 'pkcs-pass', 'keyAlias': alias, 'keyPassword': 'pkcs-pass'})
        ..files.add(await http.MultipartFile.fromPath('keystore', jks));
      final response = await http.Response.fromStream(await request.send());
      expect(response.statusCode, 200, reason: response.body);
      return jsonDecode(response.body) as Map;
    }

    expect((await validate('upload'))['valid'], isTrue);
    expect((await validate('nope'))['valid'], isFalse);
  });

  test('build request validation', () async {
    final zip = await zipSample('static-notes', tmp.path);
    final request = http.MultipartRequest('POST', base.resolve('/api/builds'))
      ..headers.addAll(auth())
      ..fields['options'] = jsonEncode({'packageName': 'bad name', 'signing': 'debug'})
      ..files.add(await http.MultipartFile.fromPath('project', zip));
    final response = await http.Response.fromStream(await request.send());
    expect(response.statusCode, 400);

    final noKeystore = http.MultipartRequest('POST', base.resolve('/api/builds'))
      ..headers.addAll(auth())
      ..fields['options'] = jsonEncode({'signing': 'keystore'})
      ..files.add(await http.MultipartFile.fromPath('project', zip));
    final r2 = await http.Response.fromStream(await noKeystore.send());
    expect(r2.statusCode, 400);
    expect(r2.body, contains('keystore'));
  });

  test('unknown build is 404', () async {
    final response = await http.get(base.resolve('/api/builds/nope'), headers: auth());
    expect(response.statusCode, 404);
  });
}
