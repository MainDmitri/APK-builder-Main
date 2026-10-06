import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:path/path.dart' as p;

import '../build_log.dart';
import '../config.dart';
import '../process_runner.dart';
import '../workspace.dart';
import 'icons.dart';
import 'manifest_tools.dart';
import 'templates.dart';

/// Wraps native Java/Kotlin sources (profile C1) into a Gradle project
/// generated from the pinned toolchain.
class NativeSourcesGenerator {
  NativeSourcesGenerator(this.config);

  final EngineConfig config;

  static final _skip = RegExp(r'(^|/)(build|\.gradle|\.idea|\.git|__MACOSX)(/|$)');

  Future<void> generate({
    required String projectDir,
    required String androidDir,
    required ProjectAnalysis analysis,
    required ResolvedAppConfig app,
    required BuildLog log,
    String? customIcon,
  }) async {
    final info = analysis.native!;
    final namespace = info.namespace!;
    TemplateRenderer.render(p.join(config.templatesDir, 'native'), androidDir, {
      'PROJECT_NAME': gradleProjectName(app.packageName),
      'AGP_VERSION': Toolchain.androidGradlePlugin,
      'KOTLIN_VERSION': Toolchain.kotlin,
    });

    final mainDir = p.join(androidDir, 'app', 'src', 'main');
    final manifestFile = File(p.join(mainDir, 'AndroidManifest.xml'));
    final permissions = app.permissions.expand((perm) => perm.manifestPermissions).toList();

    if (info.sourceSetRoot != null) {
      copyDirectory(p.join(projectDir, info.sourceSetRoot!), mainDir, exclude: (rel) => _skip.hasMatch(rel));
      var manifest = manifestFile.readAsStringSync();
      manifest = ManifestTools.ensureAndroidNamespace(manifest);
      manifest = ManifestTools.removePackageAttribute(manifest);
      manifest = ManifestTools.ensureExportedActivities(manifest);
      if (app.orientation != ScreenOrientation.sensor) {
        manifest = ManifestTools.ensureLauncherOrientation(manifest, app.orientation.androidValue);
      }
      manifest = ManifestTools.injectPermissions(manifest, permissions);
      manifestFile.writeAsStringSync(manifest);
    } else {
      _placeLooseSources(projectDir, mainDir, info, log);
      manifestFile
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(ManifestTools.generate(
          mainActivity: info.mainActivity!,
          permissions: permissions,
          orientation: app.orientation.androidValue,
        ));
      log.add('Сгенерирован AndroidManifest.xml (LAUNCHER: ${info.mainActivity}).');
    }

    final manifest = manifestFile.readAsStringSync();
    final resDir = p.join(mainDir, 'res');
    final usesAppCompat = _sourcesContain(mainDir, 'AppCompatActivity');
    _healResources(manifest, resDir, app, usesAppCompat, log);

    if (customIcon != null || ManifestTools.applicationIcon(manifest) == null) {
      // A picture chosen in the app, or no icon at all in the manifest:
      // own resource names, so nothing clashes with the project's files.
      await LauncherIconGenerator(log).generate(
        resDir: resDir,
        sourcePath: customIcon,
        themeColor: app.themeColor,
        label: app.appName,
        internalPrefix: 'appbuilder_',
        launcherName: 'appbuilder_ic_launcher',
      );
      manifestFile.writeAsStringSync(ManifestTools.setApplicationIcon(
        manifest,
        icon: '@mipmap/appbuilder_ic_launcher',
        roundIcon: '@mipmap/appbuilder_ic_launcher_round',
      ));
      log.add(customIcon != null
          ? 'Иконка приложения заменена выбранной картинкой.'
          : 'В AndroidManifest.xml не было иконки — добавлена сгенерированная.');
      _writeBuildFile(androidDir, namespace, app, info, analysis, log);
      return;
    }

    final mipmaps = ManifestTools.referencedResources(manifest, 'mipmap');
    final needLauncher = mipmaps.contains('ic_launcher') && !_resourceExists(resDir, 'mipmap', 'ic_launcher');
    final needRound = mipmaps.contains('ic_launcher_round') && !_resourceExists(resDir, 'mipmap', 'ic_launcher_round');
    if (needLauncher || needRound) {
      await LauncherIconGenerator(log).generate(
        resDir: resDir,
        sourcePath: null,
        themeColor: app.themeColor,
        label: app.appName,
        internalPrefix: 'appbuilder_',
        writeLauncher: needLauncher,
        writeRound: needRound,
      );
    }
    _writeBuildFile(androidDir, namespace, app, info, analysis, log);
  }

  void _writeBuildFile(
    String androidDir,
    String namespace,
    ResolvedAppConfig app,
    NativeProjectInfo info,
    ProjectAnalysis analysis,
    BuildLog log,
  ) {
    final buildFile = buildGradle(
      namespace: namespace,
      app: app,
      compose: info.usesCompose,
      extraDependencies: [...info.declaredDependencies, ...?analysis.config?.dependencies],
    );
    File(p.join(androidDir, 'app', 'build.gradle.kts')).writeAsStringSync(buildFile);
    log.add('Сгенерирован app/build.gradle.kts: namespace=$namespace, applicationId=${app.packageName}, '
        'Compose=${info.usesCompose ? 'да' : 'нет'}.');
  }

  void _placeLooseSources(String projectDir, String mainDir, NativeProjectInfo info, BuildLog log) {
    final packageRe = RegExp(r'^\s*package\s+([A-Za-z_][\w.]*)', multiLine: true);
    for (final rel in info.looseSources) {
      final file = File(p.join(projectDir, rel));
      final pkg = packageRe.firstMatch(file.readAsStringSync())?.group(1);
      if (pkg == null) {
        throw BuildFailure('В файле $rel нет объявления package.');
      }
      final target = File(p.joinAll([mainDir, 'java', ...pkg.split('.'), p.basename(rel)]));
      target.parent.createSync(recursive: true);
      file.copySync(target.path);
    }
    for (final rel in info.looseResources) {
      final index = rel.startsWith('res/') ? 4 : rel.indexOf('/res/') + 5;
      final target = File(p.join(mainDir, 'res', rel.substring(index)));
      target.parent.createSync(recursive: true);
      File(p.join(projectDir, rel)).copySync(target.path);
    }
    log.add('Исходники разложены по пакетам: ${info.looseSources.length} файлов, ресурсов: ${info.looseResources.length}.');
  }

  /// Adds styles / strings that the manifest references but the sources do
  /// not define (a frequent omission in AI-generated code).
  void _healResources(String manifest, String resDir, ResolvedAppConfig app, bool appCompat, BuildLog log) {
    final definedStyles = <String>{};
    final definedStrings = <String>{};
    final valuesDirs = Directory(resDir).existsSync()
        ? Directory(resDir).listSync().whereType<Directory>().where((d) => p.basename(d.path).startsWith('values'))
        : const <Directory>[];
    for (final dir in valuesDirs) {
      for (final f in dir.listSync().whereType<File>().where((f) => f.path.endsWith('.xml'))) {
        final text = f.readAsStringSync();
        definedStyles.addAll(RegExp(r'<style\s+name="([^"]+)"').allMatches(text).map((m) => m.group(1)!));
        definedStrings.addAll(RegExp(r'<string\s+name="([^"]+)"').allMatches(text).map((m) => m.group(1)!));
      }
    }
    final missingStyles = ManifestTools.referencedResources(manifest, 'style').difference(definedStyles);
    final missingStrings = ManifestTools.referencedResources(manifest, 'string').difference(definedStrings);
    if (missingStyles.isEmpty && missingStrings.isEmpty) return;

    final parent = appCompat ? 'Theme.Material3.DayNight.NoActionBar' : 'android:Theme.Material.Light.NoActionBar';
    final buffer = StringBuffer('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n');
    for (final s in missingStyles) {
      buffer.writeln('    <style name="$s" parent="$parent" />');
      log.add('Предупреждение: стиль @style/$s не найден в res/values — добавлен на основе $parent.');
    }
    for (final s in missingStrings) {
      final value = s == 'app_name' ? app.appName : s;
      buffer.writeln('    <string name="$s">${androidStringEscape(value)}</string>');
      log.add('Предупреждение: строка @string/$s не найдена — добавлена со значением «$value».');
    }
    buffer.writeln('</resources>');
    File(p.join(resDir, 'values', 'appbuilder_autogen.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(buffer.toString());
  }

  static bool _resourceExists(String resDir, String type, String name) {
    final res = Directory(resDir);
    if (!res.existsSync()) return false;
    for (final dir in res.listSync().whereType<Directory>()) {
      final base = p.basename(dir.path);
      if (base != type && !base.startsWith('$type-')) continue;
      if (dir.listSync().any((f) => p.basenameWithoutExtension(f.path) == name)) return true;
    }
    return false;
  }

  static bool _sourcesContain(String mainDir, String needle) {
    for (final sub in const ['java', 'kotlin']) {
      final dir = Directory(p.join(mainDir, sub));
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if ((f.path.endsWith('.kt') || f.path.endsWith('.java')) && f.readAsStringSync().contains(needle)) return true;
      }
    }
    return false;
  }

  /// app/build.gradle.kts for sources mode. User dependencies override the
  /// built-in ones with the same group:artifact.
  static String buildGradle({
    required String namespace,
    required ResolvedAppConfig app,
    required bool compose,
    required List<String> extraDependencies,
  }) {
    final deps = <String, String>{};
    void add(String coordinate) {
      final parts = coordinate.split(':');
      deps['${parts[0]}:${parts[1]}'] = coordinate;
    }

    Toolchain.nativeBaseDependencies.forEach(add);
    if (compose) Toolchain.composeDependencies.forEach(add);
    extraDependencies.forEach(add);

    final lines = [
      if (compose) '    implementation(platform("${Toolchain.composeBom}"))',
      ...deps.values.map((d) => '    implementation("$d")'),
    ];

    return '''
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
${compose ? '    id("org.jetbrains.kotlin.plugin.compose")\n' : ''}}

android {
    namespace = "$namespace"
    compileSdk = ${Toolchain.compileSdk}

    defaultConfig {
        applicationId = "${app.packageName}"
        minSdk = ${Toolchain.minSdk}
        targetSdk = ${Toolchain.targetSdk}
        versionCode = ${app.versionCode}
        versionName = "${app.versionName}"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
${compose ? '        compose = true\n' : ''}    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
${lines.join('\n')}
}
''';
  }
}
