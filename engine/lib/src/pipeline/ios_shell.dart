import 'dart:convert';
import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:path/path.dart' as p;

import '../build_log.dart';
import '../config.dart';
import 'icons.dart';
import 'plist.dart';
import 'templates.dart';
import 'web_shell.dart';

/// Generates the Xcode project (XcodeGen `project.yml`) of the iOS WKWebView
/// shell: Swift sources, Info.plist, app icon and the web root as `www/`.
class IosShellGenerator {
  IosShellGenerator(this.config);

  final EngineConfig config;

  static const deploymentTarget = '15.0';

  /// iOS bundle identifiers allow letters, digits, `-` and `.` (no `_`).
  static String bundleId(String packageName) => packageName.replaceAll('_', '-');

  /// `CFBundleShortVersionString`: up to three numbers (`1.2.3`).
  static String shortVersion(String versionName) =>
      RegExp(r'^\d+(\.\d+){0,2}').firstMatch(versionName.trim())?.group(0) ?? '1.0';

  static const _orientationKeys = {
    'portrait': 'UIInterfaceOrientationPortrait',
    'upside': 'UIInterfaceOrientationPortraitUpsideDown',
    'left': 'UIInterfaceOrientationLandscapeLeft',
    'right': 'UIInterfaceOrientationLandscapeRight',
  };

  static String _orientationList(List<String> keys) =>
      keys.map((k) => '\t\t<string>${_orientationKeys[k]}</string>').join('\n');

  Future<void> generate({
    required String webRoot,
    required String projectDir,
    required ResolvedAppConfig app,
    required WebRootInfo webInfo,
    required BuildLog log,
    String? customIcon,
  }) async {
    final (iphone, ipad) = switch (app.orientation) {
      ScreenOrientation.portrait => (const ['portrait'], const ['portrait', 'upside']),
      ScreenOrientation.landscape => (const ['left', 'right'], const ['left', 'right']),
      ScreenOrientation.sensor => (const ['portrait', 'left', 'right'], const ['portrait', 'upside', 'left', 'right']),
    };
    final extraKeys = [
      if (app.permissions.contains(AppPermission.location)) ...[
        '\t<key>NSLocationWhenInUseUsageDescription</key>',
        '\t<string>Приложению нужно ваше местоположение.</string>',
      ],
    ];

    TemplateRenderer.render(p.join(config.templatesDir, 'ios_shell'), projectDir, {
      'DEPLOYMENT_TARGET': deploymentTarget,
      'BUNDLE_ID': bundleId(app.packageName),
      'APP_NAME': plistEscape(app.appName),
      'VERSION_NAME': shortVersion(app.versionName),
      'VERSION_CODE': '${app.versionCode}',
      'STATUS_BAR_HIDDEN': app.fullscreen ? '<true/>' : '<false/>',
      'REQUIRES_FULL_SCREEN': app.orientation == ScreenOrientation.sensor ? '<false/>' : '<true/>',
      'ORIENTATIONS': _orientationList(iphone),
      'IPAD_ORIENTATIONS': _orientationList(ipad),
      'EXTRA_KEYS': extraKeys.join('\n'),
    });

    final appDir = p.join(projectDir, 'App');
    final www = p.join(appDir, 'www');
    var files = 0;
    for (final e in Directory(webRoot).listSync(recursive: true, followLinks: false).whereType<File>()) {
      final rel = p.relative(e.path, from: webRoot).replaceAll('\\', '/');
      if (WebShellGenerator.isExcludedAsset(rel)) continue;
      final target = File(p.join(www, rel));
      target.parent.createSync(recursive: true);
      e.copySync(target.path);
      files++;
    }
    log.add('Веб-ассеты: $files файлов → App/www/');

    final shellConfig = WebShellGenerator.shellConfigOf(app);
    File(p.join(appDir, 'appbuilder-shell.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(shellConfig));

    final assets = p.join(appDir, 'Assets.xcassets');
    final icon = await LauncherIconGenerator(log).squareIcon(
      sourcePath: customIcon ?? (webInfo.iconPath == null ? null : p.join(webRoot, webInfo.iconPath!)),
      themeColor: app.themeColor,
      label: app.appName,
    );
    final iconSet = Directory(p.join(assets, 'AppIcon.appiconset'))..createSync(recursive: true);
    File(p.join(iconSet.path, 'icon-1024.png')).writeAsBytesSync(icon);
    File(p.join(iconSet.path, 'Contents.json')).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'images': [
        {'filename': 'icon-1024.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'},
      ],
      'info': {'author': 'xcode', 'version': 1},
    }));

    final colorSet = Directory(p.join(assets, 'LaunchBackground.colorset'))..createSync(recursive: true);
    File(p.join(colorSet.path, 'Contents.json')).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
      'colors': [
        {
          'idiom': 'universal',
          'color': {'color-space': 'srgb', 'components': _components(app.backgroundColor)},
        },
      ],
      'info': {'author': 'xcode', 'version': 1},
    }));

    if (app.iosInfoPlist.isNotEmpty) {
      final plistFile = File(p.join(appDir, 'Info.plist'));
      var plist = plistFile.readAsStringSync();
      for (final entry in app.iosInfoPlist.entries) {
        plist = PlistEditor.set(plist, entry.key, entry.value);
      }
      plistFile.writeAsStringSync(plist);
      log.add('Info.plist из appbuilder.json: ${app.iosInfoPlist.keys.join(', ')}');
    }

    log.add('iOS-проект: bundle id ${bundleId(app.packageName)}, версия ${shortVersion(app.versionName)} '
        '(${app.versionCode}), iOS $deploymentTarget+, конфигурация ${jsonEncode(shellConfig)}');
  }

  static Map<String, String> _components(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', '').padRight(6, '0').substring(0, 6), radix: 16) ?? 0xFFFFFF;
    String c(int shift) => (((v >> shift) & 0xFF) / 255).toStringAsFixed(3);
    return {'red': c(16), 'green': c(8), 'blue': c(0), 'alpha': '1.000'};
  }
}
