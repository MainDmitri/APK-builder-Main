import 'dart:convert';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:test/test.dart';

/// Extracts fenced ```json blocks from a generated prompt.
List<Object?> jsonBlocks(String text) => RegExp(r'```json\n(.*?)\n```', dotAll: true)
    .allMatches(text)
    .map((m) => jsonDecode(m.group(1)!))
    .toList();

void main() {
  const generator = PromptGenerator();
  const base = PromptConfig(
    appName: 'Заметки',
    packageName: 'com.example.notes',
    description: 'Приложение для заметок с поиском и тегами.',
  );

  test('validation catches missing fields', () {
    expect(generator.validate(const PromptConfig()), isNotEmpty);
    expect(generator.validate(base), isEmpty);
    expect(generator.validate(base.copyWith(appType: PromptAppType.webService, remoteUrl: 'http://x')), isNotEmpty);
  });

  for (final type in PromptAppType.values) {
    test('every json block is valid for ${type.id}', () {
      final prompt = generator.generate(base.copyWith(appType: type, remoteUrl: 'https://api.example.com/v1'));
      expect(prompt, contains('com.example.notes'));
      final blocks = jsonBlocks(prompt);
      expect(blocks, isNotEmpty);
      final appBuilder = blocks.whereType<Map>().firstWhere((m) => m.containsKey('packageName'));
      expect(appBuilder['packageName'], 'com.example.notes');
      expect(prompt, contains('## Запрещено'));
      expect(prompt, contains('## Самопроверка'));
    });
  }

  test('technology of a configuration and platforms in the prompt', () {
    expect(PromptTech.of(base), PromptTech.javascript);
    expect(PromptTech.of(base.copyWith(appType: PromptAppType.nodeSpa, spaFramework: SpaFramework.vue)), PromptTech.vue);
    expect(PromptTech.of(base.copyWith(appType: PromptAppType.flutter)), PromptTech.flutter);
    expect(PromptTech.kotlin.iphone, isFalse);
    expect(generator.generate(base.copyWith(appType: PromptAppType.nodeSpa)), contains('| Язык / технология | React (JavaScript) |'));
    expect(generator.generate(base), contains('Android (APK) и iPhone (.ipa)'));
    expect(generator.generate(base), contains('100dvh'));
    expect(generator.generate(base.copyWith(appType: PromptAppType.nativeAndroid)), contains('| Платформы | Android (APK) |'));
  });

  test('Flutter prompt: pubspec with verified packages, no platform folders', () {
    final prompt = generator.generate(base.copyWith(
      appType: PromptAppType.flutter,
      storage: StorageKind.database,
      permissions: {AppPermission.internet, AppPermission.camera, AppPermission.notifications},
    ));
    expect(prompt, contains('для Android и iPhone'));
    expect(prompt, contains('name: notes'));
    expect(prompt, contains('sqflite: ${Toolchain.flutterPackages['sqflite']}'));
    expect(prompt, contains('image_picker: ${Toolchain.flutterPackages['image_picker']}'));
    expect(prompt, contains('Папки `android/`, `ios/`'));
    // Flutter apps are native: notifications are not filtered out like in the WebView.
    final appBuilder = jsonBlocks(prompt).whereType<Map>().firstWhere((m) => m.containsKey('packageName'));
    expect(appBuilder['permissions'], contains('notifications'));
  });

  test('node SPA uses verified versions and relative base', () {
    final prompt = generator.generate(base.copyWith(appType: PromptAppType.nodeSpa));
    final pkg = jsonBlocks(prompt).whereType<Map>().firstWhere((m) => m.containsKey('scripts'));
    expect(pkg['scripts']['build'], 'vite build');
    expect(pkg['dependencies']['react'], Toolchain.webStack['react']);
    expect(prompt, contains("base: './'"));
    expect(prompt, contains('tailwindcss()'));
  });

  test('phaser game is a node project, canvas game is static', () {
    final phaser = generator.generate(base.copyWith(appType: PromptAppType.game, gameEngine: GameEngine.phaser));
    expect(phaser, contains('"phaser"'));
    final canvas = generator.generate(base.copyWith(appType: PromptAppType.game, gameEngine: GameEngine.canvas));
    expect(canvas, isNot(contains('package.json')));
    expect(canvas, contains('"fullscreen": true'));
  });

  test('native prompt lists manifest permissions and forbids gradle files', () {
    final prompt = generator.generate(base.copyWith(
      appType: PromptAppType.nativeAndroid,
      permissions: {AppPermission.camera, AppPermission.notifications},
      storage: StorageKind.database,
    ));
    expect(prompt, contains('android.permission.CAMERA'));
    expect(prompt, contains('android.permission.POST_NOTIFICATIONS'));
    expect(prompt, contains('SQLiteOpenHelper'));
    expect(prompt, contains('app/src/main/java/com/example/notes/MainActivity.kt'));
    expect(prompt, contains('**Не создавай** `build.gradle'));
  });

  test('web prompt drops native-only permissions', () {
    final prompt = generator.generate(base.copyWith(permissions: {AppPermission.notifications, AppPermission.location}));
    final cfg = jsonBlocks(prompt).whereType<Map>().firstWhere((m) => m.containsKey('packageName'));
    expect(cfg['permissions'], ['location']);
  });

  test('full contract appendix', () {
    final prompt = generator.generate(base.copyWith(includeFullContract: true));
    expect(prompt, contains('AI Agent Contract v${Toolchain.contractVersion}'));
  });
}
