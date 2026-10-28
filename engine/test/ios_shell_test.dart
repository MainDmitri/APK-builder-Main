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
    tmp = await Directory.systemTemp.createTemp('engine-ios');
    config = testConfig(tmp.path);
    log = BuildLog(File(p.join(tmp.path, 'test.log')));
  });

  tearDown(() async {
    await log.close();
    await tmp.delete(recursive: true);
  });

  test('APK / IPA file names stay Latin for GitHub release assets', () {
    expect(BuildPipeline.latinFileBase('Bot Runner', 'com.example.bot'), 'Bot Runner');
    expect(BuildPipeline.latinFileBase('Заметки', 'net.appbuilder.samples.notes'), 'notes');
    expect(BuildPipeline.latinFileBase(null, 'com.my_company.shop_list'), 'shop-list');
  });

  test('bundle id and version for iOS', () {
    expect(IosShellGenerator.bundleId('com.my_company.app_1'), 'com.my-company.app-1');
    expect(IosShellGenerator.shortVersion('2.10.3-beta'), '2.10.3');
    expect(IosShellGenerator.shortVersion('1.2.3.4'), '1.2.3');
    expect(IosShellGenerator.shortVersion('release'), '1.0');
  });

  test('Xcode project of the WebView shell from the static sample', () async {
    final zip = await zipSample('static-notes', tmp.path);
    final projectDir = p.join(tmp.path, 'ios');
    final outcome = await BuildPipeline(config).generateIosProject(
      IosProjectRequest(
        zipPath: zip,
        workDir: p.join(tmp.path, 'work'),
        projectDir: projectDir,
        options: const BuildOptions(
          appName: 'Notes & Co',
          packageName: 'net.appbuilder.my_notes',
          orientation: ScreenOrientation.sensor,
          permissions: {AppPermission.location},
        ),
      ),
      log,
    );
    expect(outcome.bundleId, 'net.appbuilder.my-notes');
    expect(outcome.ipaFileName, 'my-notes-1.0.0.ipa');

    final plist = File(p.join(projectDir, 'App', 'Info.plist')).readAsStringSync();
    expect(plist, contains('<string>Notes &amp; Co</string>'));
    expect(plist, contains('UIInterfaceOrientationLandscapeLeft'));
    expect(plist, contains('NSLocationWhenInUseUsageDescription'));
    expect(plist, contains('<key>UIRequiresFullScreen</key>\n\t<false/>'));
    final project = File(p.join(projectDir, 'project.yml')).readAsStringSync();
    expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER: net.appbuilder.my-notes'));
    expect(project, contains('iOS: "${IosShellGenerator.deploymentTarget}"'));

    for (final f in Directory(projectDir).listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.png')) continue;
      expect(f.readAsStringSync(), isNot(contains('{{')), reason: f.path);
    }
    final app = p.join(projectDir, 'App');
    expect(File(p.join(app, 'www', 'index.html')).existsSync(), isTrue);
    expect(File(p.join(app, 'www', 'js', 'app.js')).existsSync(), isTrue);
    expect(File(p.join(app, 'www', 'appbuilder.json')).existsSync(), isFalse);
    expect(File(p.join(app, 'Sources', 'WebViewController.swift')).existsSync(), isTrue);

    final shell = jsonDecode(File(p.join(app, 'appbuilder-shell.json')).readAsStringSync()) as Map;
    expect(shell['startUrl'], 'index.html');

    final icon = img.decodePng(
        File(p.join(app, 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png')).readAsBytesSync())!;
    expect([icon.width, icon.height], [1024, 1024]);
    expect(icon.numChannels, 3, reason: 'iOS app icons must be opaque');
    final colors = jsonDecode(
        File(p.join(app, 'Assets.xcassets', 'LaunchBackground.colorset', 'Contents.json')).readAsStringSync()) as Map;
    expect(((colors['colors'] as List).single as Map)['color'], isNotNull);
  });

  test('native Android projects are rejected for iOS', () async {
    final zip = await zipSample('native-compose', tmp.path);
    expect(
      () => BuildPipeline(config).generateIosProject(
        IosProjectRequest(zipPath: zip, workDir: p.join(tmp.path, 'work'), projectDir: p.join(tmp.path, 'ios')),
        log,
      ),
      throwsA(isA<BuildFailure>().having((e) => e.message, 'message', contains('код Kotlin/Java работает только на Android'))),
    );
  });
}
