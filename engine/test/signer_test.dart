import 'dart:io';

import 'package:appbuilder_engine/engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory tmp;
  late ApkSigner signer;
  late BuildLog log;
  late String jks;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('engine-signer');
    signer = ApkSigner(testConfig(tmp.path));
    log = BuildLog(File(p.join(tmp.path, 'signer.log')));
    jks = p.join(tmp.path, 'release.jks');
    final r = await Process.run('keytool', [
      '-genkeypair', '-noprompt', '-keystore', jks, '-storetype', 'JKS', '-storepass', 'store-pass-1', //
      '-keypass', 'key-pass-1', '-alias', 'release', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '30',
      '-dname', 'CN=Test,O=AppBuilder,C=RU',
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  tearDownAll(() async {
    await log.close();
    await tmp.delete(recursive: true);
  });

  KeystoreSpec spec({String store = 'store-pass-1', String alias = 'release', String key = 'key-pass-1'}) =>
      KeystoreSpec(path: jks, storePassword: store, alias: alias, keyPassword: key);

  test('valid keystore', () async {
    final check = await signer.validate(spec(), log);
    expect(check.valid, isTrue, reason: check.error);
    expect(check.aliases, ['release']);
    expect(check.owner, contains('CN=Test'));
    expect(check.sha256, matches(RegExp(r'^[0-9A-F:]{95}$')));
  });

  test('alias is case-insensitive', () async {
    expect((await signer.validate(spec(alias: 'RELEASE'), log)).valid, isTrue);
  });

  test('wrong store password', () async {
    final check = await signer.validate(spec(store: 'wrong-pass'), log);
    expect(check.valid, isFalse);
    expect(check.error, contains('storePassword'));
  });

  test('unknown alias', () async {
    final check = await signer.validate(spec(alias: 'upload'), log);
    expect(check.valid, isFalse);
    expect(check.error, contains('release'));
  });

  test('wrong key password', () async {
    final check = await signer.validate(spec(key: 'wrong-key'), log);
    expect(check.valid, isFalse);
    expect(check.error, contains('keyPassword'));
  });

  test('not a keystore', () async {
    final bogus = File(p.join(tmp.path, 'bogus.jks'))..writeAsStringSync('hello world');
    final check = await signer.validate(
      KeystoreSpec(path: bogus.path, storePassword: 'whatever', alias: 'a', keyPassword: 'whatever'),
      log,
    );
    expect(check.valid, isFalse);
  });

  test('debug keystore is created once', () async {
    final ks = await signer.debugKeystore(log);
    expect(File(ks.path).existsSync(), isTrue);
    expect((await signer.validate(ks, log)).valid, isTrue);
  });

  test('passwords never reach the log', () {
    final text = File(p.join(tmp.path, 'signer.log')).readAsStringSync();
    expect(text, isNot(contains('store-pass-1')));
    expect(text, isNot(contains('key-pass-1')));
  });
}
