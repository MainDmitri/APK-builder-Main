import 'package:archive/archive.dart';
import 'dart:convert';
import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:appbuilder_engine/engine.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late Directory tmp;
  late EngineConfig config;
  late BuildLog log;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('engine-gen');
    config = testConfig(tmp.path);
    log = BuildLog(File(p.join(tmp.path, 'test.log')));
  });

  tearDown(() async {
    await log.close();
    await tmp.delete(recursive: true);
  });

  ProjectAnalysis analyzeSample(String name) => const ProjectAnalyzer().analyze(DirectorySource(p.join('samples', name)));

  test('web shell from the static sample', () async {
    final analysis = analyzeSample('static-notes');
    final app = ResolvedAppConfig.resolve(analysis, const BuildOptions(permissions: {AppPermission.storage, AppPermission.location}));
    final webRoot = p.join('samples', 'static-notes');
    final source = DirectorySource(webRoot);
    final info = ProjectAnalyzer.inspectWebRoot(source.paths.toSet(), source.readText, []);
    expect(info.iconPath, 'icon.svg');

    final android = p.join(tmp.path, 'android');
    await WebShellGenerator(config).generate(webRoot: webRoot, androidDir: android, app: app, webInfo: info, log: log);

    final main = p.join(android, 'app', 'src', 'main');
    final manifest = File(p.join(main, 'AndroidManifest.xml')).readAsStringSync();
    expect(manifest, contains('android:screenOrientation="portrait"'));
    expect(manifest, contains('android.permission.ACCESS_FINE_LOCATION'));
    expect(manifest, contains('android:maxSdkVersion="28"'));
    expect(manifest, isNot(contains('{{')));

    final gradle = File(p.join(android, 'app', 'build.gradle.kts')).readAsStringSync();
    expect(gradle, contains('applicationId = "net.appbuilder.samples.notes"'));
    expect(gradle, contains(Toolchain.webkitDependency));
    expect(File(p.join(android, 'build.gradle.kts')).readAsStringSync(), contains(Toolchain.androidGradlePlugin));

    expect(File(p.join(main, 'assets', 'www', 'index.html')).existsSync(), isTrue);
    expect(File(p.join(main, 'assets', 'www', 'js', 'app.js')).existsSync(), isTrue);
    expect(File(p.join(main, 'assets', 'www', 'appbuilder.json')).existsSync(), isFalse);

    final shell = jsonDecode(File(p.join(main, 'assets', 'appbuilder-shell.json')).readAsStringSync()) as Map;
    expect(shell['startUrl'], 'index.html');
    expect(shell['themeColor'], '#1565C0');

    expect(File(p.join(main, 'res', 'values', 'strings.xml')).readAsStringSync(), contains('>Заметки<'));
    for (final entry in LauncherIconGenerator.densities.entries) {
      final png = img.decodePng(File(p.join(main, 'res', 'mipmap-${entry.key}', 'ic_launcher.png')).readAsBytesSync())!;
      expect(png.width, (48 * entry.value).round());
      final fg = img.decodePng(File(p.join(main, 'res', 'mipmap-${entry.key}', 'ic_launcher_foreground.png')).readAsBytesSync())!;
      expect(fg.width, (108 * entry.value).round());
    }
    expect(File(p.join(main, 'res', 'mipmap-anydpi-v26', 'ic_launcher_round.xml')).existsSync(), isTrue);
    for (final f in Directory(android).listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.png')) continue;
      expect(f.readAsStringSync(), isNot(contains('{{')), reason: f.path);
    }
  });

  test('native compose sources get compose plugin, BOM and generated icons', () async {
    final analysis = analyzeSample('native-compose');
    final app = ResolvedAppConfig.resolve(analysis, const BuildOptions(permissions: {AppPermission.camera}));
    final android = p.join(tmp.path, 'android');
    await NativeSourcesGenerator(config).generate(
      projectDir: p.join('samples', 'native-compose'),
      androidDir: android,
      analysis: analysis,
      app: app,
      log: log,
    );
    final gradle = File(p.join(android, 'app', 'build.gradle.kts')).readAsStringSync();
    expect(gradle, contains('id("org.jetbrains.kotlin.plugin.compose")'));
    expect(gradle, contains('compose = true'));
    expect(gradle, contains('platform("${Toolchain.composeBom}")'));
    expect(gradle, contains('namespace = "net.appbuilder.samples.counter"'));
    final main = p.join(android, 'app', 'src', 'main');
    final manifest = File(p.join(main, 'AndroidManifest.xml')).readAsStringSync();
    expect(manifest, contains('android.permission.CAMERA'));
    expect(File(p.join(main, 'java', 'net', 'appbuilder', 'samples', 'counter', 'MainActivity.kt')).existsSync(), isTrue);
    expect(File(p.join(main, 'res', 'mipmap-xxxhdpi', 'appbuilder_ic_launcher_foreground.png')).existsSync(), isTrue);
    expect(File(p.join(main, 'res', 'mipmap-anydpi-v26', 'ic_launcher_round.xml')).readAsStringSync(),
        contains('@color/appbuilder_ic_launcher_background'));
  });

  String redIcon() {
    final picture = img.Image(width: 64, height: 64, numChannels: 4);
    img.fill(picture, color: img.ColorRgba8(255, 0, 0, 255));
    final file = File(p.join(tmp.path, 'icon.png'))..writeAsBytesSync(img.encodePng(picture));
    return file.path;
  }

  test('custom icon replaces the web project icon', () async {
    final analysis = analyzeSample('static-notes');
    final app = ResolvedAppConfig.resolve(analysis, const BuildOptions());
    final webRoot = p.join('samples', 'static-notes');
    final source = DirectorySource(webRoot);
    final info = ProjectAnalyzer.inspectWebRoot(source.paths.toSet(), source.readText, []);
    final android = p.join(tmp.path, 'android');
    await WebShellGenerator(config)
        .generate(webRoot: webRoot, androidDir: android, app: app, webInfo: info, log: log, customIcon: redIcon());
    final res = p.join(android, 'app', 'src', 'main', 'res');
    expect(File(p.join(res, 'values', 'launcher_colors.xml')).readAsStringSync(), contains('#FF0000'));
    final legacy = img.decodePng(File(p.join(res, 'mipmap-xxxhdpi', 'ic_launcher.png')).readAsBytesSync())!;
    final center = legacy.getPixel(legacy.width ~/ 2, legacy.height ~/ 2);
    expect([center.r, center.g, center.b], [255, 0, 0]);
  });

  test('custom icon for native sources gets its own resource names', () async {
    final analysis = analyzeSample('native-compose');
    final app = ResolvedAppConfig.resolve(analysis, const BuildOptions());
    final android = p.join(tmp.path, 'android');
    await NativeSourcesGenerator(config).generate(
      projectDir: p.join('samples', 'native-compose'),
      androidDir: android,
      analysis: analysis,
      app: app,
      log: log,
      customIcon: redIcon(),
    );
    final main = p.join(android, 'app', 'src', 'main');
    final manifest = File(p.join(main, 'AndroidManifest.xml')).readAsStringSync();
    expect(ManifestTools.applicationIcon(manifest), '@mipmap/appbuilder_ic_launcher');
    expect(manifest, contains('android:roundIcon="@mipmap/appbuilder_ic_launcher_round"'));
    expect(File(p.join(main, 'res', 'mipmap-mdpi', 'appbuilder_ic_launcher.png')).existsSync(), isTrue);
    expect(File(p.join(main, 'res', 'mipmap-anydpi-v26', 'appbuilder_ic_launcher_round.xml')).existsSync(), isTrue);
    expect(File(p.join(android, 'app', 'build.gradle.kts')).existsSync(), isTrue);
  });

  test('manifest without an icon gets a generated one', () async {
    final project = Directory(p.join(tmp.path, 'noicon'))..createSync();
    Directory(p.join(project.path, 'app', 'src', 'main', 'java', 'com', 'noicon')).createSync(recursive: true);
    File(p.join(project.path, 'app', 'src', 'main', 'AndroidManifest.xml')).writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="NoIcon" android:theme="@android:style/Theme.Material.Light">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
''');
    File(p.join(project.path, 'app', 'src', 'main', 'java', 'com', 'noicon', 'MainActivity.kt')).writeAsStringSync(
        'package com.noicon\n\nimport android.app.Activity\n\nclass MainActivity : Activity()\n');
    final analysis = const ProjectAnalyzer().analyze(DirectorySource(project.path));
    expect(analysis.kind, ProjectKind.nativeSources, reason: analysis.errors.join());
    final app = ResolvedAppConfig.resolve(analysis, const BuildOptions(packageName: 'com.noicon'));
    final android = p.join(tmp.path, 'android');
    await NativeSourcesGenerator(config).generate(
      projectDir: p.join(project.path, analysis.rootPrefix),
      androidDir: android,
      analysis: analysis,
      app: app,
      log: log,
    );
    final main = p.join(android, 'app', 'src', 'main');
    expect(ManifestTools.applicationIcon(File(p.join(main, 'AndroidManifest.xml')).readAsStringSync()),
        '@mipmap/appbuilder_ic_launcher');
    expect(File(p.join(main, 'res', 'mipmap-xhdpi', 'appbuilder_ic_launcher.png')).existsSync(), isTrue);
  });

  test('java views sources: package attribute removed, exported added, no compose', () async {
    final analysis = analyzeSample('native-views');
    expect(analysis.native!.label, 'Чаевые');
    final app = ResolvedAppConfig.resolve(analysis, const BuildOptions());
    expect(app.appName, 'Чаевые');
    final android = p.join(tmp.path, 'android');
    await NativeSourcesGenerator(config).generate(
      projectDir: p.join('samples', 'native-views', analysis.rootPrefix),
      androidDir: android,
      analysis: analysis,
      app: app,
      log: log,
    );
    final main = p.join(android, 'app', 'src', 'main');
    final manifest = File(p.join(main, 'AndroidManifest.xml')).readAsStringSync();
    expect(manifest, isNot(contains('package=')));
    expect(manifest, contains('android:exported="true"'));
    final gradle = File(p.join(android, 'app', 'build.gradle.kts')).readAsStringSync();
    expect(gradle, isNot(contains('compose')));
    expect(gradle, contains('viewBinding = true'));
    expect(File(p.join(main, 'res', 'mipmap-mdpi', 'ic_launcher.png')).existsSync(), isTrue);
    expect(File(p.join(main, 'res', 'mipmap-mdpi', 'ic_launcher_round.png')).existsSync(), isFalse);
    expect(File(p.join(main, 'res', 'values', 'appbuilder_autogen.xml')).existsSync(), isFalse);
  });

  test('missing theme and strings are healed for loose sources', () async {
    final project = Directory(p.join(tmp.path, 'loose'))..createSync();
    File(p.join(project.path, 'MainActivity.kt')).writeAsStringSync(
        'package com.loose.demo\n\nimport android.app.Activity\n\nclass MainActivity : Activity()\n');
    final analysis = const ProjectAnalyzer().analyze(DirectorySource(project.path));
    expect(analysis.canBuild, isTrue, reason: analysis.errors.join());
    final app = ResolvedAppConfig.resolve(analysis, const BuildOptions(appName: 'Loose'));
    final android = p.join(tmp.path, 'android');
    await NativeSourcesGenerator(config).generate(
      projectDir: project.path,
      androidDir: android,
      analysis: analysis,
      app: app,
      log: log,
    );
    final main = p.join(android, 'app', 'src', 'main');
    expect(File(p.join(main, 'java', 'com', 'loose', 'demo', 'MainActivity.kt')).existsSync(), isTrue);
    final healed = File(p.join(main, 'res', 'values', 'appbuilder_autogen.xml')).readAsStringSync();
    expect(healed, contains('<style name="Theme.App" parent="android:Theme.Material.Light.NoActionBar" />'));
    expect(healed, contains('<string name="app_name">Loose</string>'));
    expect(File(p.join(main, 'AndroidManifest.xml')).readAsStringSync(), contains('com.loose.demo.MainActivity'));
  });

  test('node output directory detection', () {
    final project = Directory(p.join(tmp.path, 'node'))..createSync();
    Directory(p.join(project.path, 'dist', 'my-app', 'browser')).createSync(recursive: true);
    File(p.join(project.path, 'dist', 'my-app', 'browser', 'index.html')).writeAsStringSync('');
    expect(NodeStage.findOutputDir(project.path, ['dist', 'build']), p.join(project.path, 'dist', 'my-app', 'browser'));
    expect(NodeStage.findOutputDir(project.path, ['../outside']), isNull);
  });

  test('zip extraction rejects path traversal', () async {
    final zip = File(p.join(tmp.path, 'evil.zip'));
    // Hand-made archive with an entry named ../evil.txt
    final archive = await _zipWithEntry('../evil.txt');
    zip.writeAsBytesSync(archive);
    expect(
      () => extractZipSafely(zip.path, p.join(tmp.path, 'out'), maxBytes: 1 << 20, maxEntries: 10),
      throwsA(isA<BuildFailure>()),
    );
  });

  test('gradle error summary', () {
    final summary = GradleStage.summarizeGradleErrors([
      '> Task :app:compileReleaseKotlin FAILED',
      'e: file:///x/MainActivity.kt:10:5 Unresolved reference: foo',
      '* What went wrong:',
      "Execution failed for task ':app:compileReleaseKotlin'.",
      '* Try:',
    ]);
    expect(summary, contains('Unresolved reference'));
    expect(summary, contains('Execution failed'));
  });
}

Future<List<int>> _zipWithEntry(String name) async {
  final archive = Archive()..addFile(ArchiveFile.bytes(name, utf8.encode('x')));
  return ZipEncoder().encodeBytes(archive);
}
