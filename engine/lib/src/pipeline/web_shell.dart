import 'dart:convert';
import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:path/path.dart' as p;

import '../build_log.dart';
import '../config.dart';
import 'icons.dart';
import 'templates.dart';

/// Stage 2 for web projects: generates the Android WebView shell project and
/// copies the web root into `assets/www/`.
class WebShellGenerator {
  WebShellGenerator(this.config);

  final EngineConfig config;

  static final _excluded = RegExp(r'(^|/)(\.git|__MACOSX|\.DS_Store|Thumbs\.db)(/|$)|\.(jks|keystore|p12|pfx)$');

  Future<void> generate({
    required String webRoot,
    required String androidDir,
    required ResolvedAppConfig app,
    required WebRootInfo webInfo,
    required BuildLog log,
    String? customIcon,
  }) async {
    final permissions = app.permissions
        .where(AppPermission.webSupported.contains)
        .expand((perm) => perm.manifestPermissions)
        .map((m) => '    ${m.toXml()}')
        .join('\n');

    TemplateRenderer.render(p.join(config.templatesDir, 'web_shell'), androidDir, {
      'PROJECT_NAME': gradleProjectName(app.packageName),
      'AGP_VERSION': Toolchain.androidGradlePlugin,
      'COMPILE_SDK': '${Toolchain.compileSdk}',
      'MIN_SDK': '${Toolchain.minSdk}',
      'TARGET_SDK': '${Toolchain.targetSdk}',
      'APPLICATION_ID': app.packageName,
      'VERSION_CODE': '${app.versionCode}',
      'VERSION_NAME': app.versionName,
      'WEBKIT_DEPENDENCY': Toolchain.webkitDependency,
      'CORE_DEPENDENCY': Toolchain.coreDependency,
      'PERMISSIONS': permissions.isEmpty ? '    <!-- no permissions -->' : permissions,
      'ORIENTATION': app.orientation.androidValue,
    });

    final mainDir = p.join(androidDir, 'app', 'src', 'main');
    final www = p.join(mainDir, 'assets', 'www');
    var files = 0;
    for (final e in Directory(webRoot).listSync(recursive: true, followLinks: false).whereType<File>()) {
      final rel = p.relative(e.path, from: webRoot).replaceAll('\\', '/');
      if (rel == 'appbuilder.json' || _excluded.hasMatch(rel)) continue;
      final target = File(p.join(www, rel));
      target.parent.createSync(recursive: true);
      e.copySync(target.path);
      files++;
    }
    log.add('Веб-ассеты: $files файлов → assets/www/');

    final shellConfig = {
      'startUrl': app.startUrl,
      'fullscreen': app.fullscreen,
      'themeColor': app.themeColor,
      'backgroundColor': app.backgroundColor,
      'openLinksExternally': app.openLinksExternally,
    };
    File(p.join(mainDir, 'assets', 'appbuilder-shell.json'))
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(shellConfig));
    log.add('Конфигурация оболочки: ${jsonEncode(shellConfig)}');

    final values = Directory(p.join(mainDir, 'res', 'values'))..createSync(recursive: true);
    File(p.join(values.path, 'strings.xml')).writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">${androidStringEscape(app.appName)}</string>
</resources>
''');
    File(p.join(values.path, 'colors.xml')).writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="shell_background">${app.backgroundColor}</color>
    <color name="shell_theme">${app.themeColor}</color>
</resources>
''');

    await LauncherIconGenerator(log).generate(
      resDir: p.join(mainDir, 'res'),
      sourcePath: customIcon ?? (webInfo.iconPath == null ? null : p.join(webRoot, webInfo.iconPath!)),
      themeColor: app.themeColor,
      label: app.appName,
    );
  }
}
