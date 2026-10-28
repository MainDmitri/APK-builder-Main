import 'dart:convert';
import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:path/path.dart' as p;

import '../build_log.dart';
import '../config.dart';
import '../process_runner.dart';
import '../workspace.dart';
import 'icons.dart';
import 'ios_shell.dart';
import 'manifest_tools.dart';
import 'plist.dart';
import 'templates.dart';

/// Flutter projects (profile D): creates missing platform folders with
/// `flutter create`, writes the app identity (package / bundle id, name,
/// version, permissions, orientation, icon) and builds the release APK.
/// The .ipa is built on macOS by .github/scripts/ios-build.sh.
class FlutterStage {
  FlutterStage(this.config, {this.runner = const ProcessRunner()});

  final EngineConfig config;
  final ProcessRunner runner;

  Map<String, String> get _environment => {
        'ANDROID_HOME': config.androidHome,
        'ANDROID_SDK_ROOT': config.androidHome,
        'GRADLE_USER_HOME': config.gradleUserHome,
        'FLUTTER_SUPPRESS_ANALYTICS': 'true',
        'CI': 'true',
      };

  Future<void> ensureAvailable(BuildLog log) async {
    final ProcessResultLines result;
    try {
      result = await runner.run(
        [config.flutterCommand, '--version'],
        workingDirectory: Directory.systemTemp.path,
        log: log,
        environment: _environment,
        timeout: const Duration(minutes: 5),
      );
    } on BuildFailure {
      throw BuildFailure('Flutter SDK не найден на сервере сборки. Flutter-проекты собираются в режиме '
          '«GitHub Actions» или на сервере с установленным Flutter ${Toolchain.flutter} (переменная APPBUILDER_FLUTTER).');
    }
    if (result.exitCode != 0) throw BuildFailure('Flutter SDK не запускается (код ${result.exitCode}).');
  }

  /// Prepares [projectDir] for the given [platforms] (`android`, `ios`).
  Future<void> prepare({
    required String projectDir,
    required ProjectAnalysis analysis,
    required ResolvedAppConfig app,
    required Set<String> platforms,
    required BuildLog log,
    String? customIcon,
  }) async {
    final info = analysis.flutter!;
    for (final generated in ['build', '.dart_tool']) {
      deleteQuietly(p.join(projectDir, generated));
    }
    final versionName = platforms.contains('ios') ? IosShellGenerator.shortVersion(app.versionName) : app.versionName;
    setPubspecVersion(p.join(projectDir, 'pubspec.yaml'), '$versionName+${app.versionCode}');
    log.add('pubspec.yaml: version: $versionName+${app.versionCode}');

    final missing = platforms.where((platform) => !Directory(p.join(projectDir, platform)).existsSync()).toList()..sort();
    if (missing.isNotEmpty) {
      final dot = app.packageName.lastIndexOf('.');
      final org = dot > 0 ? app.packageName.substring(0, dot) : 'com.appbuilder';
      await runner.runChecked(
        [
          config.flutterCommand,
          'create',
          '--no-pub',
          '--platforms=${missing.join(',')}',
          '--org',
          org,
          '--project-name',
          info.packageName,
          '.',
        ],
        workingDirectory: projectDir,
        log: log,
        environment: _environment,
        failureMessage: 'flutter create не смог создать папки ${missing.join(', ')}',
        timeout: const Duration(minutes: 5),
      );
      log.add('Созданы папки платформ: ${missing.join(', ')}.');
    }

    // A project without its own platform folders has no icon of its own either.
    if (platforms.contains('android')) {
      await _android(projectDir, app, log, icon: customIcon != null || missing.contains('android'), customIcon: customIcon);
    }
    if (platforms.contains('ios')) {
      await _ios(projectDir, app, log, icon: customIcon != null || missing.contains('ios'), customIcon: customIcon);
    }
  }

  /// `flutter pub get` + `flutter build apk --release`.
  Future<String> buildApk(String projectDir, BuildLog log) async {
    final pub = await runner.run(
      [config.flutterCommand, 'pub', 'get'],
      workingDirectory: projectDir,
      log: log,
      environment: _environment,
      timeout: config.nodeInstallTimeout,
    );
    if (pub.exitCode != 0) {
      throw BuildFailure('flutter pub get: не удалось установить пакеты.\n${summarizeErrors(pub.output)}');
    }
    final build = await runner.run(
      [config.flutterCommand, 'build', 'apk', '--release'],
      workingDirectory: projectDir,
      log: log,
      environment: _environment,
      timeout: config.gradleTimeout,
    );
    if (build.exitCode != 0) {
      throw BuildFailure('Flutter: сборка завершилась ошибкой.\n${summarizeErrors(build.output)}');
    }
    final apk = File(p.join(projectDir, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'));
    if (!apk.existsSync()) throw BuildFailure('flutter build apk завершился, но app-release.apk не найден.');
    log.add('Собран: ${p.relative(apk.path, from: projectDir)}');
    return apk.path;
  }

  /// `flutter pub get` + `flutter analyze lib`: compile errors are found on
  /// Linux in a minute instead of after a long Xcode build on macOS.
  Future<void> checkDart(String projectDir, BuildLog log) async {
    final pub = await runner.run(
      [config.flutterCommand, 'pub', 'get'],
      workingDirectory: projectDir,
      log: log,
      environment: _environment,
      timeout: config.nodeInstallTimeout,
    );
    if (pub.exitCode != 0) {
      throw BuildFailure('flutter pub get: не удалось установить пакеты.\n${summarizeErrors(pub.output)}');
    }
    final analyze = await runner.run(
      [config.flutterCommand, 'analyze', '--no-pub', '--no-fatal-infos', '--no-fatal-warnings', 'lib'],
      workingDirectory: projectDir,
      log: log,
      environment: _environment,
      timeout: config.nodeInstallTimeout,
    );
    final errors = analyzerErrors(analyze.output);
    if (errors.isNotEmpty) {
      throw BuildFailure('Ошибки в коде Dart — приложение не скомпилируется (сборка на macOS не запускалась):\n'
          '${errors.take(20).map((e) => '- $e').join('\n')}'
          '${errors.length > 20 ? '\n- …и ещё ${errors.length - 20}' : ''}');
    }
    log.add('Код Dart проверен: ошибок компиляции нет.');
  }

  /// `error • message • lib/a.dart:1:2 • code` lines of `flutter analyze` → `lib/a.dart:1:2: message`.
  static List<String> analyzerErrors(List<String> output) => [
        for (final line in output)
          if (RegExp(r'^\s*error • (.+?) • (\S+:\d+:\d+) • ').firstMatch(line) case final m?) '${m[2]}: ${m[1]}',
      ];

  /// Dart compiler, pub and Gradle errors from the tool output.
  static String summarizeErrors(List<String> output) {
    final interesting = RegExp(r'(: Error: |^Error: |^error: |^e: |Because .* depends on|version solving failed|'
        r"FAILURE: |What went wrong|Could not|doesn't exist|isn't defined|The getter|The method)");
    final lines = output.where(interesting.hasMatch).map((l) => l.trim()).toSet().take(20).toList();
    final picked = lines.isNotEmpty ? lines : output.skip(output.length > 15 ? output.length - 15 : 0).toList();
    return picked.map((l) => '- $l').join('\n');
  }

  /// Writes `version: <value>` into pubspec.yaml.
  static void setPubspecVersion(String pubspecPath, String version) {
    final file = File(pubspecPath);
    final text = file.readAsStringSync();
    final line = RegExp(r'^version:.*$', multiLine: true);
    file.writeAsStringSync(line.hasMatch(text)
        ? text.replaceFirst(line, 'version: $version')
        : text.replaceFirstMapped(RegExp(r'^(name:.*)$', multiLine: true), (m) => '${m.group(1)}\nversion: $version'));
  }

  // ---------------------------------------------------------------- Android

  Future<void> _android(String projectDir, ResolvedAppConfig app, BuildLog log,
      {required bool icon, String? customIcon}) async {
    final appDir = p.join(projectDir, 'android', 'app');
    for (final name in ['build.gradle.kts', 'build.gradle']) {
      final gradle = File(p.join(appDir, name));
      if (!gradle.existsSync()) continue;
      final text = gradle.readAsStringSync();
      final patched = text.replaceAllMapped(
        RegExp(r'''applicationId(\s*=?\s*)["'][^"']*["']'''),
        (m) => 'applicationId${m.group(1)}"${app.packageName}"',
      );
      gradle.writeAsStringSync(patched);
      log.add('android/app/$name: applicationId = ${app.packageName}');
    }

    final manifestFile = File(p.join(appDir, 'src', 'main', 'AndroidManifest.xml'));
    if (manifestFile.existsSync()) {
      var manifest = manifestFile.readAsStringSync();
      manifest = setApplicationLabel(manifest, app.appName);
      manifest = ManifestTools.injectPermissions(manifest, app.manifestPermissions);
      if (app.orientation != ScreenOrientation.sensor) {
        manifest = ManifestTools.ensureLauncherOrientation(manifest, app.orientation.androidValue);
      }
      manifestFile.writeAsStringSync(manifest);
      log.add('AndroidManifest.xml: название «${app.appName}», разрешения: '
          '${[...app.permissions.map((e) => e.id), ...app.extraAndroidPermissions].join(', ')}');
    }

    if (icon) {
      final res = Directory(p.join(appDir, 'src', 'main', 'res'));
      if (res.existsSync()) {
        for (final f in res.listSync(recursive: true).whereType<File>()) {
          final name = p.basename(f.path);
          if (p.basename(f.parent.path).startsWith('mipmap') && name.startsWith('ic_launcher')) f.deleteSync();
        }
      }
      await LauncherIconGenerator(log).generate(
        resDir: res.path,
        sourcePath: customIcon,
        themeColor: app.themeColor,
        label: app.appName,
        internalPrefix: 'appbuilder_',
      );
    }
  }

  /// Sets android:label of `<application>` to a literal value.
  static String setApplicationLabel(String manifest, String label) {
    final match = RegExp(r'<application\b[^>]*>', dotAll: true).firstMatch(manifest);
    if (match == null) return manifest;
    final value = androidStringEscape(label).replaceAll('"', '&quot;');
    var tag = match.group(0)!;
    final existing = RegExp(r'android:label\s*=\s*"[^"]*"');
    tag = existing.hasMatch(tag)
        ? tag.replaceFirst(existing, 'android:label="$value"')
        : tag.replaceFirst('<application', '<application android:label="$value"');
    return manifest.replaceRange(match.start, match.end, tag);
  }

  // -------------------------------------------------------------------- iOS

  static const _orientationKeys = {
    'portrait': 'UIInterfaceOrientationPortrait',
    'upside': 'UIInterfaceOrientationPortraitUpsideDown',
    'left': 'UIInterfaceOrientationLandscapeLeft',
    'right': 'UIInterfaceOrientationLandscapeRight',
  };

  static const _usageDescriptions = {
    AppPermission.camera: {'NSCameraUsageDescription': 'Приложению нужен доступ к камере.'},
    AppPermission.microphone: {'NSMicrophoneUsageDescription': 'Приложению нужен доступ к микрофону.'},
    AppPermission.location: {'NSLocationWhenInUseUsageDescription': 'Приложению нужно ваше местоположение.'},
    AppPermission.storage: {
      'NSPhotoLibraryUsageDescription': 'Приложению нужен доступ к фотографиям.',
      'NSPhotoLibraryAddUsageDescription': 'Приложение сохраняет файлы в «Фото».',
    },
    AppPermission.wifi: {
      'NSLocalNetworkUsageDescription': 'Приложению нужен доступ к устройствам в вашей локальной сети.',
    },
  };

  Future<void> _ios(String projectDir, ResolvedAppConfig app, BuildLog log,
      {required bool icon, String? customIcon}) async {
    final bundleId = IosShellGenerator.bundleId(app.packageName);
    final pbxproj = File(p.join(projectDir, 'ios', 'Runner.xcodeproj', 'project.pbxproj'));
    if (pbxproj.existsSync()) {
      final text = pbxproj.readAsStringSync();
      final current = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = "?([A-Za-z0-9.\-]+?)"?;')
          .allMatches(text)
          .map((m) => m.group(1)!)
          .firstWhere((id) => !id.endsWith('.RunnerTests'), orElse: () => '');
      if (current.isNotEmpty) {
        pbxproj.writeAsStringSync(text.replaceAllMapped(
          RegExp('PRODUCT_BUNDLE_IDENTIFIER = "?${RegExp.escape(current)}(\\.RunnerTests)?"?;'),
          (m) => 'PRODUCT_BUNDLE_IDENTIFIER = $bundleId${m.group(1) ?? ''};',
        ));
        log.add('ios/Runner.xcodeproj: bundle id $current → $bundleId');
      }
    }

    final plistFile = File(p.join(projectDir, 'ios', 'Runner', 'Info.plist'));
    if (plistFile.existsSync()) {
      var plist = plistFile.readAsStringSync();
      plist = setPlistString(plist, 'CFBundleDisplayName', app.appName);
      for (final permission in app.permissions) {
        for (final entry in (_usageDescriptions[permission] ?? const <String, String>{}).entries) {
          if (!PlistEditor.hasKey(plist, entry.key)) plist = PlistEditor.set(plist, entry.key, entry.value);
        }
      }
      // HTTP to devices in the local network (WebView, url_launcher, NSURLSession-based plugins).
      if (app.permissions.contains(AppPermission.wifi) && !PlistEditor.hasKey(plist, 'NSAppTransportSecurity')) {
        plist = PlistEditor.set(plist, 'NSAppTransportSecurity', const {'NSAllowsLocalNetworking': true});
      }
      if (app.orientation != ScreenOrientation.sensor) {
        final keys = app.orientation == ScreenOrientation.portrait ? const ['portrait'] : const ['left', 'right'];
        final ipadKeys = app.orientation == ScreenOrientation.portrait ? const ['portrait', 'upside'] : keys;
        plist = setPlistStringArray(plist, 'UISupportedInterfaceOrientations', keys.map((k) => _orientationKeys[k]!).toList());
        plist = setPlistStringArray(
            plist, 'UISupportedInterfaceOrientations~ipad', ipadKeys.map((k) => _orientationKeys[k]!).toList());
      }
      for (final entry in app.iosInfoPlist.entries) {
        plist = PlistEditor.set(plist, entry.key, entry.value);
      }
      plistFile.writeAsStringSync(plist);
      log.add('Info.plist: название «${app.appName}», ориентация ${app.orientation.id}'
          '${app.iosInfoPlist.isEmpty ? '' : ', из appbuilder.json: ${app.iosInfoPlist.keys.join(', ')}'}');
    }

    if (icon) {
      final iconSet = Directory(p.join(projectDir, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'));
      deleteQuietly(iconSet.path);
      iconSet.createSync(recursive: true);
      final png = await LauncherIconGenerator(log).squareIcon(
        sourcePath: customIcon,
        themeColor: app.themeColor,
        label: app.appName,
      );
      File(p.join(iconSet.path, 'icon-1024.png')).writeAsBytesSync(png);
      File(p.join(iconSet.path, 'Contents.json')).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'images': [
          {'filename': 'icon-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'},
        ],
        'info': {'author': 'xcode', 'version': 1},
      }));
    }
  }

  /// Sets `<key>` → `<string>` in an XML property list (top-level dict).
  static String setPlistString(String plist, String key, String value) => PlistEditor.set(plist, key, value);

  static String setPlistStringArray(String plist, String key, List<String> values) => PlistEditor.set(plist, key, values);
}
