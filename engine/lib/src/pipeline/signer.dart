import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../build_log.dart';
import '../config.dart';
import '../process_runner.dart';

/// Keystore and credentials used for signing.
class KeystoreSpec {
  const KeystoreSpec({
    required this.path,
    required this.storePassword,
    required this.alias,
    required this.keyPassword,
  });

  final String path;
  final String storePassword;
  final String alias;
  final String keyPassword;
}

class KeystoreCheck {
  const KeystoreCheck({
    required this.valid,
    this.error,
    this.aliases = const [],
    this.storeType,
    this.owner,
    this.sha256,
    this.validUntil,
  });

  final bool valid;
  final String? error;
  final List<String> aliases;
  final String? storeType;
  final String? owner;
  final String? sha256;
  final String? validUntil;

  Map<String, Object?> toJson() => {
        'valid': valid,
        if (error != null) 'error': error,
        'aliases': aliases,
        if (storeType != null) 'storeType': storeType,
        if (owner != null) 'owner': owner,
        if (sha256 != null) 'sha256': sha256,
        if (validUntil != null) 'validUntil': validUntil,
      };
}

class SignResult {
  const SignResult(this.certificateSha256, this.schemes);

  final String? certificateSha256;
  final List<String> schemes;
}

/// zipalign + apksigner (v1/v2/v3) + keytool validation.
class ApkSigner {
  ApkSigner(this.config, {this.runner = const ProcessRunner()});

  final EngineConfig config;
  final ProcessRunner runner;

  static const _storeEnv = 'APPBUILDER_STORE_PASS';
  static const _keyEnv = 'APPBUILDER_KEY_PASS';

  /// The engine's persistent debug key (same as Android Studio's defaults).
  Future<KeystoreSpec> debugKeystore(BuildLog log) async {
    final path = config.debugKeystorePath;
    if (!File(path).existsSync()) {
      Directory(config.keysDir).createSync(recursive: true);
      log.add('Создаю debug-keystore движка: $path');
      await runner.runChecked(
        [
          'keytool', '-genkeypair', '-noprompt', //
          '-keystore', path, '-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android',
          '-alias', 'androiddebugkey', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000',
          '-dname', 'CN=Android Debug,O=Android,C=US',
        ],
        workingDirectory: config.dataDir,
        log: log,
        failureMessage: 'keytool не смог создать debug-keystore',
      );
    }
    return KeystoreSpec(path: path, storePassword: 'android', alias: 'androiddebugkey', keyPassword: 'android');
  }

  /// Checks store password, alias and key password with keytool.
  Future<KeystoreCheck> validate(KeystoreSpec ks, BuildLog log) async {
    log
      ..addSecret(ks.storePassword)
      ..addSecret(ks.keyPassword);
    final env = {_storeEnv: ks.storePassword, _keyEnv: ks.keyPassword};
    final list = await runner.run(
      ['keytool', '-J-Duser.language=en', '-list', '-v', '-keystore', ks.path, '-storepass:env', _storeEnv],
      workingDirectory: p.dirname(ks.path),
      log: log,
      environment: env,
      logOutput: false,
      timeout: const Duration(minutes: 1),
    );
    final out = list.output.join('\n');
    if (list.exitCode != 0) {
      final error = out.contains('password was incorrect') || out.contains('tampered')
          ? 'Неверный пароль хранилища (storePassword).'
          : (out.contains('Invalid keystore format') || out.contains('Unrecognized keystore format') || out.contains('not a valid')
              ? 'Файл не является keystore (ожидается JKS или PKCS12).'
              : 'keytool не смог открыть keystore: ${list.output.where((l) => l.contains('keytool error')).join(' ')}');
      return KeystoreCheck(valid: false, error: error);
    }

    final aliases = RegExp(r'^Alias name:\s*(.+)$', multiLine: true).allMatches(out).map((m) => m.group(1)!.trim()).toList();
    final storeType = RegExp(r'^Keystore type:\s*(.+)$', multiLine: true).firstMatch(out)?.group(1)?.trim();
    final alias = aliases.firstWhere((a) => a.toLowerCase() == ks.alias.toLowerCase(), orElse: () => '');
    if (alias.isEmpty) {
      return KeystoreCheck(
        valid: false,
        error: 'Alias «${ks.alias}» не найден. Доступные: ${aliases.join(', ')}.',
        aliases: aliases,
        storeType: storeType,
      );
    }

    final block = _aliasBlock(out, alias);
    final owner = RegExp(r'^Owner:\s*(.+)$', multiLine: true).firstMatch(block)?.group(1)?.trim();
    final sha256 = RegExp(r'SHA256:\s*([0-9A-F:]+)').firstMatch(block)?.group(1);
    final until = RegExp(r'until:\s*(.+)$', multiLine: true).firstMatch(block)?.group(1)?.trim();

    final keyOk = await _keyPasswordWorks(ks, alias, ks.keyPassword, log);
    if (!keyOk) {
      return KeystoreCheck(
        valid: false,
        error: 'Неверный пароль ключа (keyPassword) для «$alias».',
        aliases: aliases,
        storeType: storeType,
      );
    }
    return KeystoreCheck(
      valid: true,
      aliases: aliases,
      storeType: storeType,
      owner: owner,
      sha256: sha256,
      validUntil: until,
    );
  }

  Future<bool> _keyPasswordWorks(KeystoreSpec ks, String alias, String keyPassword, BuildLog log) async {
    final tmp = await Directory.systemTemp.createTemp('appbuilder-csr');
    try {
      final r = await runner.run(
        [
          'keytool', '-J-Duser.language=en', '-certreq', '-alias', alias, '-keystore', ks.path, //
          '-storepass:env', _storeEnv, '-keypass:env', _keyEnv, '-file', p.join(tmp.path, 'req.csr'),
        ],
        workingDirectory: tmp.path,
        log: log,
        environment: {_storeEnv: ks.storePassword, _keyEnv: keyPassword},
        logOutput: false,
        timeout: const Duration(minutes: 1),
      );
      return r.exitCode == 0;
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  static String _aliasBlock(String listing, String alias) {
    final start = listing.indexOf(RegExp('^Alias name:\\s*${RegExp.escape(alias)}\\s*\$', multiLine: true));
    if (start < 0) return listing;
    final next = listing.indexOf('Alias name:', start + 11);
    return listing.substring(start, next < 0 ? listing.length : next);
  }

  void _requireTools() {
    final zipalign = config.zipalignPath;
    if (zipalign == null || config.apksignerPath == null || !File(zipalign).existsSync()) {
      throw BuildFailure('Не найдены Android build-tools (zipalign/apksigner) в ${config.androidHome}/build-tools.');
    }
  }

  /// `zipalign -p -f 4` (page-aligned native libraries).
  Future<void> align({required String input, required String output, required BuildLog log}) async {
    _requireTools();
    Directory(p.dirname(output)).createSync(recursive: true);
    await runner.runChecked(
      [config.zipalignPath!, '-p', '-f', '4', input, output],
      workingDirectory: p.dirname(output),
      log: log,
      failureMessage: 'zipalign завершился ошибкой',
    );
  }

  /// `apksigner sign` with v1 + v2 + v3 schemes.
  Future<void> sign({
    required String input,
    required String output,
    required KeystoreSpec keystore,
    required BuildLog log,
  }) async {
    _requireTools();
    log
      ..addSecret(keystore.storePassword)
      ..addSecret(keystore.keyPassword);
    var signed = await _sign(config.apksignerPath!, input, output, keystore, keystore.keyPassword, log);
    if (!signed && keystore.keyPassword != keystore.storePassword) {
      // PKCS12 keys are usually protected by the store password.
      log.add('Подпись с keyPassword не удалась — пробую пароль хранилища (PKCS12).');
      signed = await _sign(config.apksignerPath!, input, output, keystore, keystore.storePassword, log);
    }
    if (!signed) throw BuildFailure('apksigner не смог подписать APK: проверьте alias и пароли.');
  }

  /// `apksigner verify` — returns the verified schemes and certificate digest.
  Future<SignResult> verify({required String apk, required BuildLog log}) async {
    _requireTools();
    final verify = await runner.runChecked(
      [config.apksignerPath!, 'verify', '--verbose', '--print-certs', apk],
      workingDirectory: p.dirname(apk),
      log: log,
      failureMessage: 'Проверка подписи (apksigner verify) не пройдена',
    );
    final text = verify.output.join('\n');
    final schemes = RegExp(r'Verified using (v[\d.]+) scheme \([^)]*\): true')
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toList();
    // With minSdk >= 24 apksigner verify skips the JAR (v1) scheme, so its
    // presence is checked directly in the archive.
    if (!schemes.contains('v1') && await hasJarSignature(apk)) schemes.insert(0, 'v1');
    final sha = RegExp(r'certificate SHA-256 digest:\s*([0-9a-f]+)').firstMatch(text)?.group(1);
    return SignResult(sha, schemes);
  }

  /// True when the APK carries a v1 (JAR) signature: META-INF/*.SF plus a
  /// signature block (*.RSA / *.DSA / *.EC).
  static Future<bool> hasJarSignature(String apkPath) async {
    final input = InputFileStream(apkPath);
    try {
      final names = ZipDecoder().decodeStream(input).map((f) => f.name).toList();
      bool has(RegExp re) => names.any(re.hasMatch);
      return has(RegExp(r'^META-INF/[^/]+\.SF$')) && has(RegExp(r'^META-INF/[^/]+\.(RSA|DSA|EC)$'));
    } finally {
      await input.close();
    }
  }

  Future<bool> _sign(String apksigner, String input, String output, KeystoreSpec ks, String keyPassword, BuildLog log) async {
    final r = await runner.run(
      [
        apksigner, 'sign', //
        '--ks', ks.path,
        '--ks-key-alias', ks.alias,
        '--ks-pass', 'env:$_storeEnv',
        '--key-pass', 'env:$_keyEnv',
        '--v1-signing-enabled', 'true',
        '--v2-signing-enabled', 'true',
        '--v3-signing-enabled', 'true',
        '--out', output,
        input,
      ],
      workingDirectory: p.dirname(output),
      log: log,
      environment: {_storeEnv: ks.storePassword, _keyEnv: keyPassword},
    );
    return r.exitCode == 0;
  }
}
