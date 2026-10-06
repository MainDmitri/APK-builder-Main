import 'dart:typed_data';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('static web', () {
    test('index.html in root with manifest and icon', () {
      final a = analyzeFiles({
        'index.html': '<html><head><link rel="manifest" href="./manifest.json"></head>'
            '<body><script type="module" src="./js/app.js"></script></body></html>',
        'manifest.json': '{"name":"Notes","theme_color":"#112233","display":"fullscreen",'
            '"icons":[{"src":"./icon.svg","sizes":"any"},{"src":"missing.png","sizes":"192x192"}]}',
        'icon.svg': '<svg/>',
        'js/app.js': 'console.log(1)',
      });
      expect(a.kind, ProjectKind.staticWeb);
      expect(a.canBuild, isTrue);
      expect(a.manifest?.name, 'Notes');
      expect(a.manifestPath, 'manifest.json');
      expect(a.warnings.any((w) => w.contains('missing.png')), isTrue);
      expect(a.plan.stages, contains(BuildStage.webAssets));
      expect(a.plan.stages, isNot(contains(BuildStage.nodeInstall)));
    });

    test('nested wrapper folder is stripped with a warning', () {
      final a = analyzeFiles({'my-app/index.html': '<html></html>', 'my-app/app.js': ''});
      expect(a.kind, ProjectKind.staticWeb);
      expect(a.rootPrefix, 'my-app/');
      expect(a.warnings.first, contains('my-app/'));
    });

    test('absolute and cleartext paths are reported', () {
      final a = analyzeFiles({
        'index.html': '<script src="/app.js"></script><img src="http://x.com/a.png"><a href="//cdn.x/y">',
      });
      expect(a.warnings.any((w) => w.contains('/app.js')), isTrue);
      expect(a.warnings.any((w) => w.contains('http://x.com/a.png')), isTrue);
    });

    test('macOS metadata is ignored', () {
      final a = analyzeFiles({'index.html': '', '__MACOSX/._index.html': '', '.DS_Store': ''});
      expect(a.kind, ProjectKind.staticWeb);
      expect(a.rootPrefix, '');
    });
  });

  group('node', () {
    test('vite + pnpm lockfile', () {
      final a = analyzeFiles({
        'package.json': '{"name":"my-cool-app","version":"2.1.0","scripts":{"build":"vite build"},'
            '"devDependencies":{"vite":"^8.0.0"}}',
        'pnpm-lock.yaml': '',
        'vite.config.js': "export default { base: './' }",
        'index.html': '<div id="app"></div>',
      });
      expect(a.kind, ProjectKind.nodeProject);
      expect(a.node!.packageManager, PackageManager.pnpm);
      expect(a.node!.framework, 'vite');
      expect(a.node!.outputDirCandidates.first, 'dist');
      expect(a.node!.buildCommand, ['pnpm', 'run', 'build']);
      expect(a.warnings.where((w) => w.contains('base')), isEmpty);
      expect(a.plan.stages.take(3), [BuildStage.extract, BuildStage.nodeInstall, BuildStage.nodeBuild]);
    });

    test('vite without relative base produces a warning; custom outDir first', () {
      final a = analyzeFiles({
        'package.json': '{"scripts":{"build":"vite build"},"dependencies":{"vite":"8"}}',
        'package-lock.json': '{}',
        'vite.config.ts': "export default { build: { outDir: 'www-out' } }",
      });
      expect(a.node!.packageManager, PackageManager.npm);
      expect(a.node!.installCommand.take(2), ['npm', 'ci']);
      expect(a.node!.outputDirCandidates.first, 'www-out');
      expect(a.warnings.any((w) => w.contains("base: './'")), isTrue);
    });

    test('appbuilder.json outputDir wins and CRA detected', () {
      final a = analyzeFiles({
        'package.json': '{"scripts":{"build":"react-scripts build"},"dependencies":{"react-scripts":"5"}}',
        'appbuilder.json': '{"web":{"outputDir":"./custom/"}}',
      });
      expect(a.node!.framework, 'cra');
      expect(a.node!.outputDirCandidates.take(2), ['custom', 'build']);
    });

    test('missing build script is an error', () {
      final a = analyzeFiles({'package.json': '{"scripts":{"start":"node x"}}'});
      expect(a.kind, ProjectKind.nodeProject);
      expect(a.canBuild, isFalse);
    });

    test('package.json without build but with index.html falls back to static', () {
      final a = analyzeFiles({'package.json': '{"devDependencies":{"prettier":"3"}}', 'index.html': ''});
      expect(a.kind, ProjectKind.staticWeb);
    });

    test('broken package.json', () {
      final a = analyzeFiles({'package.json': '{oops'});
      expect(a.canBuild, isFalse);
      expect(a.errors.single, contains('JSON'));
    });
  });

  group('native', () {
    test('sources mode app/src/main with compose', () {
      final a = analyzeFiles({
        'appbuilder.json': '{"packageName":"com.example.notes"}',
        'app/src/main/AndroidManifest.xml': '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:label="@string/app_name"><activity android:name=".MainActivity" android:exported="true"><intent-filter>'
            '<action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/>'
            '</intent-filter></activity></application></manifest>',
        'app/src/main/java/com/example/notes/MainActivity.kt':
            'package com.example.notes\nimport androidx.compose.material3.Text\nclass MainActivity : ComponentActivity()',
        'app/src/main/res/values/strings.xml': '<resources><string name="app_name">Notes \\\'X\\\'</string></resources>',
      });
      expect(a.kind, ProjectKind.nativeSources);
      expect(a.native!.label, "Notes 'X'");
      expect(a.canBuild, isTrue, reason: a.errors.join());
      expect(a.native!.sourceSetRoot, 'app/src/main');
      expect(a.native!.namespace, 'com.example.notes');
      expect(a.native!.mainActivity, 'com.example.notes.MainActivity');
      expect(a.native!.usesCompose, isTrue);
      expect(a.native!.usesKotlin, isTrue);
    });

    test('module build.gradle dependencies are picked up; package attribute warned', () {
      final a = analyzeFiles({
        'app/build.gradle.kts': 'dependencies { implementation("io.coil-kt:coil:2.7.0")\n implementation(libs.x) }',
        'app/src/main/AndroidManifest.xml': '<manifest package="org.demo.app"><application>'
            '<activity android:name="org.demo.app.Main"><intent-filter><category android:name="android.intent.category.LAUNCHER"/>'
            '</intent-filter></activity></application></manifest>',
        'app/src/main/java/org/demo/app/Main.java': 'package org.demo.app; public class Main extends Activity {}',
      });
      expect(a.kind, ProjectKind.nativeSources);
      expect(a.native!.declaredDependencies, ['io.coil-kt:coil:2.7.0']);
      expect(a.native!.namespace, 'org.demo.app');
      expect(a.native!.usesKotlin, isFalse);
      expect(a.warnings.any((w) => w.contains('package')), isTrue);
    });

    test('manifest without launcher is an error', () {
      final a = analyzeFiles({
        'src/main/AndroidManifest.xml': '<manifest><application/></manifest>',
        'src/main/java/a/b/X.kt': 'package a.b',
        'appbuilder.json': '{}',
      });
      expect(a.canBuild, isFalse);
    });

    test('loose kotlin sources generate a manifest', () {
      final a = analyzeFiles({
        'MainActivity.kt': 'package com.foo.bar\n\nclass MainActivity : AppCompatActivity() {}',
        'Helper.kt': 'package com.foo.bar.util\nobject Helper',
        'res/values/strings.xml': '<resources/>',
      });
      expect(a.kind, ProjectKind.nativeSources);
      expect(a.canBuild, isTrue, reason: a.errors.join());
      expect(a.native!.sourceSetRoot, isNull);
      expect(a.native!.mainActivity, 'com.foo.bar.MainActivity');
      expect(a.native!.looseSources, hasLength(2));
      expect(a.native!.looseResources, ['res/values/strings.xml']);
    });

    test('gradle project without wrapper jar', () {
      final a = analyzeFiles({
        'settings.gradle.kts': 'rootProject.name = "x"\ninclude(":app")',
        'build.gradle.kts': '',
        'gradlew': '#!/bin/sh',
        'gradle/wrapper/gradle-wrapper.properties': 'distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.3-bin.zip',
        'app/build.gradle.kts': 'plugins { alias(libs.plugins.android.application) }\n'
            'android { namespace = "com.x.y"\n defaultConfig { applicationId = "com.x.y.app" } }',
        'app/src/main/AndroidManifest.xml': '<manifest><application><activity android:name=".MainActivity">'
            '<intent-filter><category android:name="android.intent.category.LAUNCHER"/></intent-filter>'
            '</activity></application></manifest>',
        'app/src/main/java/com/x/y/MainActivity.kt': 'package com.x.y',
      });
      expect(a.kind, ProjectKind.nativeGradle);
      expect(a.canBuild, isTrue, reason: a.errors.join());
      expect(a.native!.appModule, 'app');
      expect(a.native!.hasUsableWrapper, isFalse);
      expect(a.native!.wrapperGradleVersion, '8.14.3');
      expect(a.native!.applicationId, 'com.x.y.app');
      expect(a.native!.mainActivity, 'com.x.y.MainActivity');
      expect(a.warnings.any((w) => w.contains('Wrapper')), isTrue);
    });
  });

  group('nested project root', () {
    test('client/ next to server/ and README is built as static web', () {
      final a = analyzeFiles({
        'README.md': '# Fullstack',
        'server/index.js': 'require("express")',
        'server/package.json': '{"scripts":{"start":"node index.js"}}',
        'client/index.html': '<link rel="manifest" href="./manifest.json"><script src="./app.js"></script>',
        'client/app.js': '',
        'client/manifest.json': '{"name":"Client App"}',
      });
      expect(a.kind, ProjectKind.staticWeb);
      expect(a.canBuild, isTrue, reason: a.errors.join());
      expect(a.rootPrefix, 'client/');
      expect(a.manifest?.name, 'Client App');
      expect(a.warnings.first, contains('client/'));
      expect(a.warnings.first, contains('server/'));
    });

    test('Vite app in frontend/ wins over express server/', () {
      final a = analyzeFiles({
        'server/package.json': '{"scripts":{"start":"node index.js"}}',
        'frontend/package.json': '{"scripts":{"build":"vite build"},"devDependencies":{"vite":"8"}}',
        'frontend/index.html': '',
        'frontend/public/index.html': '',
        'appbuilder.json': '{"appName":"Root Config","packageName":"com.root.app"}',
      });
      expect(a.kind, ProjectKind.nodeProject);
      expect(a.rootPrefix, 'frontend/');
      expect(a.node!.framework, 'vite');
      expect(a.config?.appName, 'Root Config');
    });

    test('Kotlin backend sources do not hide the web client', () {
      final a = analyzeFiles({
        'backend/src/main/kotlin/Main.kt': 'package app\nfun main() {}',
        'backend/build.gradle.kts': 'plugins { kotlin("jvm") }',
        'web/index.html': '',
      });
      expect(a.kind, ProjectKind.staticWeb);
      expect(a.rootPrefix, 'web/');
    });

    test('Gradle project in android/ subfolder', () {
      final a = analyzeFiles({
        'README.md': '',
        'android/settings.gradle.kts': 'include(":app")',
        'android/app/build.gradle.kts': 'plugins { id("com.android.application") }',
        'android/app/src/main/AndroidManifest.xml': '<manifest><application><activity android:name=".Main">'
            '<intent-filter><category android:name="android.intent.category.LAUNCHER"/></intent-filter>'
            '</activity></application></manifest>',
      });
      expect(a.kind, ProjectKind.nativeGradle);
      expect(a.rootPrefix, 'android/');
      expect(a.native!.appModule, 'app');
    });

    test('nothing buildable is reported with the archive contents', () {
      final a = analyzeFiles({'README.md': '', 'data/values.csv': ''});
      expect(a.kind, ProjectKind.unsupported);
      expect(a.errors.single, contains('data/'));
    });
  });

  test('keystore files and symlinks are reported', () {
    final a = analyzeFiles({'index.html': '', 'release.jks': 'x'});
    expect(a.warnings.any((w) => w.contains('release.jks')), isTrue);
  });

  test('not a zip', () {
    expect(() => ZipMemorySource.fromBytes(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });
}
