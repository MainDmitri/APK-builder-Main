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
    expect(PromptTech.of(base.copyWith(platform: PromptPlatform.iphone, appType: PromptAppType.nativeAndroid)), PromptTech.flutter);
    expect(generator.generate(base.copyWith(appType: PromptAppType.nodeSpa)), contains('| Язык / технология | React (JavaScript) |'));
    expect(generator.generate(base), contains('| Платформа | Android (APK)'));
    expect(generator.generate(base), isNot(contains('iPhone')));
  });

  test('iPhone prompt: real Flutter app with Info.plist keys and iOS network rules', () {
    final prompt = generator.generate(base.copyWith(
      platform: PromptPlatform.iphone,
      appType: PromptAppType.utility,
      permissions: {AppPermission.internet, AppPermission.wifi, AppPermission.camera, AppPermission.notifications},
    ));
    expect(prompt, contains('приложение для **iPhone**'));
    expect(prompt, contains('| Платформа | iPhone (.ipa), iOS 13'));
    expect(prompt, contains('flutter build ios --release --no-codesign'));
    expect(prompt, contains('network_info_plus: ${Toolchain.flutterPackages['network_info_plus']}'));
    expect(prompt, contains('connectivity_plus: ${Toolchain.flutterPackages['connectivity_plus']}'));
    expect(prompt, contains('NSLocalNetworkUsageDescription'));
    expect(prompt, contains('com.apple.developer.networking.multicast'));
    expect(prompt, contains('getWifiName()'));
    expect(prompt, contains('permission_handler'));
    expect(prompt, contains('## Интерфейс в стиле iPhone'));
    final appBuilder = jsonBlocks(prompt).whereType<Map>().firstWhere((m) => m.containsKey('packageName'));
    final plist = (appBuilder['ios'] as Map)['infoPlist'] as Map;
    expect(plist.keys, containsAll(['NSCameraUsageDescription', 'NSLocalNetworkUsageDescription', 'NSLocationWhenInUseUsageDescription']));
    expect(appBuilder['permissions'], containsAll(['wifi', 'notifications']));
    // The generated appbuilder.json is accepted by the analyzer as is.
    final errors = <String>[], warnings = <String>[];
    final parsed = AppBuilderConfig.parse(jsonEncode(appBuilder), errors, warnings);
    expect(errors, isEmpty);
    expect(warnings, isEmpty);
    expect(parsed.iosInfoPlist.keys, plist.keys);
  });

  test('Flutter prompt: pubspec with verified packages, no platform folders', () {
    final prompt = generator.generate(base.copyWith(
      appType: PromptAppType.flutter,
      storage: StorageKind.database,
      permissions: {AppPermission.internet, AppPermission.camera, AppPermission.notifications},
    ));
    expect(prompt, contains('Android-приложение «Заметки» на Flutter'));
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
