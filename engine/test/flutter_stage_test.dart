import 'dart:convert';
import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:appbuilder_engine/engine.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers.dart';

bool _flutterInstalled() {
  try {
    return Process.runSync(Platform.environment['APPBUILDER_FLUTTER'] ?? 'flutter', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('helpers', () {
    test('pubspec version is replaced or added', () {
      final dir = Directory.systemTemp.createTempSync('pubspec');
      final file = File(p.join(dir.path, 'pubspec.yaml'))..writeAsStringSync('name: a\nversion: 1.0.0+1\n');
      FlutterStage.setPubspecVersion(file.path, '2.3.0+9');
      expect(file.readAsStringSync(), 'name: a\nversion: 2.3.0+9\n');
      file.writeAsStringSync('name: a\nenvironment:\n  sdk: ^3.13.0\n');
      FlutterStage.setPubspecVersion(file.path, '1.0.0+2');
      expect(file.readAsStringSync(), startsWith('name: a\nversion: 1.0.0+2\n'));
      dir.deleteSync(recursive: true);
    });

    test('application label is a literal value', () {
      const manifest = '<manifest><application\n  android:label="old" android:icon="@mipmap/ic_launcher"></application></manifest>';
      final patched = FlutterStage.setApplicationLabel(manifest, 'Мой "счётчик" & Co');
      expect(patched, contains(r'android:label="Мой \&quot;счётчик\&quot; &amp; Co"'));
      expect(FlutterStage.setApplicationLabel('<manifest><application></application></manifest>', 'A'),
          contains('<application android:label="A">'));
    });

    test('plist strings and arrays', () {
      const plist = '<plist><dict>\n\t<key>CFBundleDisplayName</key>\n\t<string>Old</string>\n'
          '\t<key>UISupportedInterfaceOrientations</key>\n\t<array>\n\t\t<string>X</string>\n\t</array>\n</dict></plist>';
      var out = FlutterStage.setPlistString(plist, 'CFBundleDisplayName', 'A & B');
      out = FlutterStage.setPlistString(out, 'NSCameraUsageDescription', 'Камера');
      out = FlutterStage.setPlistStringArray(out, 'UISupportedInterfaceOrientations', ['UIInterfaceOrientationPortrait']);
      expect(out, contains('<string>A &amp; B</string>'));
      expect(out, contains('<key>NSCameraUsageDescription</key>\n\t<string>Камера</string>\n</dict>'));
      expect(out, contains('<string>UIInterfaceOrientationPortrait</string>'));
      expect(out, isNot(contains('<string>X</string>')));
    });

    test('error summary keeps compiler and pub errors', () {
      final summary = FlutterStage.summarizeErrors([
        'Running Gradle task',
        "lib/main.dart:12:5: Error: The method 'foo' isn't defined for the type 'Bar'.",
        'Because app depends on http ^9.0.0 which doesn\'t match any versions, version solving failed.',
      ]);
      expect(summary, contains('lib/main.dart:12:5: Error'));
      expect(summary, contains('version solving failed'));
      expect(summary, isNot(contains('Running Gradle task')));
    });
  });

  test('a lib-only project gets android/ and ios/ with the app identity', () async {
    final tmp = await Directory.systemTemp.createTemp('engine-flutter');
    final log = BuildLog(File(p.join(tmp.path, 'test.log')));
    try {
      final project = p.join(tmp.path, 'project');
      copyDirectory(p.join('samples', 'flutter-counter'), project);
      final config = File(p.join(project, 'appbuilder.json'));
      config.writeAsStringSync(jsonEncode({
        ...jsonDecode(config.readAsStringSync()) as Map<String, dynamic>,
        'ios': {
          'infoPlist': {
            'NSLocalNetworkUsageDescription': 'Поиск камер в сети',
            'NSBonjourServices': ['_http._tcp'],
          },
        },
      }));
      final analysis = const ProjectAnalyzer().analyze(DirectorySource(project));
      expect(analysis.kind, ProjectKind.flutterProject);
      final app = ResolvedAppConfig.resolve(
        analysis,
        const BuildOptions(
          appName: 'Мой счётчик',
          packageName: 'com.example.my_counter',
          versionCode: 7,
          orientation: ScreenOrientation.landscape,
          permissions: {AppPermission.camera, AppPermission.location, AppPermission.wifi},
        ),
      );
      await FlutterStage(testConfig(tmp.path)).prepare(
        projectDir: project,
        analysis: analysis,
        app: app,
        platforms: const {'android', 'ios'},
        log: log,
      );

      expect(File(p.join(project, 'pubspec.yaml')).readAsStringSync(), contains('version: 1.0.0+7'));
      final gradle = File(p.join(project, 'android', 'app', 'build.gradle.kts')).readAsStringSync();
      expect(gradle, contains('applicationId = "com.example.my_counter"'));
      final manifest = File(p.join(project, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')).readAsStringSync();
      expect(manifest, contains('android:label="Мой счётчик"'));
      expect(manifest, contains('android.permission.CAMERA'));
      expect(manifest, contains('android.permission.ACCESS_WIFI_STATE'));
      expect(manifest, contains('android:screenOrientation="sensorLandscape"'));
      final res = p.join(project, 'android', 'app', 'src', 'main', 'res');
      final icon = img.decodePng(File(p.join(res, 'mipmap-xxxhdpi', 'ic_launcher.png')).readAsBytesSync())!;
      expect(icon.width, 192);
      expect(File(p.join(res, 'mipmap-anydpi-v26', 'ic_launcher.xml')).existsSync(), isTrue);

      final pbxproj = File(p.join(project, 'ios', 'Runner.xcodeproj', 'project.pbxproj')).readAsStringSync();
      expect(pbxproj, contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.my-counter;'));
      expect(pbxproj, contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.my-counter.RunnerTests;'));
      final plist = File(p.join(project, 'ios', 'Runner', 'Info.plist')).readAsStringSync();
      expect(plist, contains('<string>Мой счётчик</string>'));
      expect(plist, contains('NSCameraUsageDescription'));
      expect(plist, contains('NSLocationWhenInUseUsageDescription'));
      expect(plist, contains('<key>NSLocalNetworkUsageDescription</key>\n\t<string>Поиск камер в сети</string>'));
      expect(plist, contains('<string>_http._tcp</string>'));
      expect(plist, contains('<key>NSAllowsLocalNetworking</key>'));
      expect(plist, contains('UIApplicationSceneManifest'));
      expect(plist, contains('UIInterfaceOrientationLandscapeLeft'));
      expect(plist, isNot(contains('<string>UIInterfaceOrientationPortrait</string>')));
      final iconSet = Directory(p.join(project, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset'));
      expect(iconSet.listSync().map((e) => p.basename(e.path)).toSet(), {'Contents.json', 'icon-1024.png'});
    } finally {
      await log.close();
      await tmp.delete(recursive: true);
    }
  }, skip: _flutterInstalled() ? false : 'Flutter SDK не установлен', timeout: const Timeout(Duration(minutes: 5)));
}
