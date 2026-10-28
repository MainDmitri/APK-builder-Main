import 'models.dart';

enum PromptAppType {
  utility('utility', 'Инструмент / Утилита', 'Калькулятор, конвертер, заметки, трекер привычек'),
  webService('web-service', 'Веб-сервис / PWA-клиент', 'Клиент для сайта, дашборд, клиент REST API'),
  game('game', '2D Canvas / WebGL игра', 'Phaser, Three.js, чистый Canvas'),
  nativeAndroid('native', 'Нативный Android-проект', 'Камера, датчики, сервисы на Kotlin'),
  nodeSpa('node-spa', 'Node.js SPA', 'React или Vue + Vite + Tailwind'),
  flutter('flutter', 'Flutter', 'Нативное приложение на Dart');

  const PromptAppType(this.id, this.title, this.examples);

  final String id;
  final String title;
  final String examples;

  bool get isNative => this == PromptAppType.nativeAndroid;
  bool get isFlutter => this == PromptAppType.flutter;

  /// HTML/JS projects running in the WebView shell.
  bool get usesWebView => !isNative && !isFlutter;
}

/// Platform a prompt is written for: separate, platform-specific prompts.
enum PromptPlatform {
  android('Android', 'APK для телефонов и планшетов Android: веб, React, Vue, Flutter или Kotlin'),
  iphone('iPhone', '.ipa для iPhone: настоящее нативное приложение на Flutter (Dart)');

  const PromptPlatform(this.title, this.description);

  final String title;
  final String description;
}

/// Language / technology of an Android prompt (iPhone prompts are always
/// Flutter). Maps onto [PromptAppType] and [SpaFramework].
enum PromptTech {
  javascript('HTML + JavaScript', 'Без сборки: утилиты, клиенты сайтов и API, игры на Canvas / Phaser / Three.js'),
  react('React (JavaScript)', 'React 19 + Vite + Tailwind CSS: сложные интерфейсы, много экранов'),
  vue('Vue (JavaScript)', 'Vue 3 + Vite + Tailwind CSS: сложные интерфейсы, много экранов'),
  flutter('Flutter (Dart)', 'Нативное приложение: быстрый интерфейс, плагины pub.dev'),
  kotlin('Kotlin', 'Нативный Android: Jetpack Compose или XML-разметка, полный доступ к Android API');

  const PromptTech(this.title, this.description);

  final String title;
  final String description;

  static PromptTech of(PromptConfig c) => switch (c.effectiveType) {
        PromptAppType.nodeSpa => c.spaFramework == SpaFramework.react ? react : vue,
        PromptAppType.flutter => flutter,
        PromptAppType.nativeAndroid => kotlin,
        PromptAppType.utility || PromptAppType.webService || PromptAppType.game => javascript,
      };
}

enum GameEngine {
  canvas('Чистый Canvas 2D (без сборки)'),
  phaser('Phaser 3 + Vite'),
  three('Three.js (WebGL) + Vite');

  const GameEngine(this.title);

  final String title;
}

enum WebServiceMode {
  remoteSite('Обёртка существующего сайта'),
  apiClient('Свой интерфейс для REST API');

  const WebServiceMode(this.title);

  final String title;
}

enum SpaFramework {
  react('React + Vite + Tailwind CSS'),
  vue('Vue 3 + Vite + Tailwind CSS');

  const SpaFramework(this.title);

  final String title;
}

enum NativeUi {
  compose('Jetpack Compose (Material 3)'),
  views('XML-разметка (View + Material Components)');

  const NativeUi(this.title);

  final String title;
}

enum StorageKind {
  none('Не нужно'),
  keyValue('Ключ-значение: LocalStorage / SharedPreferences'),
  database('База данных: IndexedDB / SQLite');

  const StorageKind(this.title);

  final String title;
}

enum TargetAi {
  chatgpt('ChatGPT'),
  claude('Claude'),
  deepseek('DeepSeek'),
  other('Другая модель');

  const TargetAi(this.title);

  final String title;
}

enum UiLanguage {
  ru('Русский'),
  en('English');

  const UiLanguage(this.title);

  final String title;
}

/// Everything the user picks in the prompt wizard.
class PromptConfig {
  const PromptConfig({
    this.platform = PromptPlatform.android,
    this.appType = PromptAppType.utility,
    this.appName = '',
    this.packageName = '',
    this.versionName = '1.0.0',
    this.orientation = ScreenOrientation.portrait,
    this.permissions = const {AppPermission.internet},
    this.storage = StorageKind.keyValue,
    this.description = '',
    this.themeColor = '#1565C0',
    this.uiLanguage = UiLanguage.ru,
    this.targetAi = TargetAi.chatgpt,
    this.gameEngine = GameEngine.canvas,
    this.webServiceMode = WebServiceMode.apiClient,
    this.remoteUrl = '',
    this.spaFramework = SpaFramework.react,
    this.nativeUi = NativeUi.compose,
    this.includeFullContract = false,
  });

  final PromptPlatform platform;

  /// Ignored for iPhone prompts: they are always Flutter (see [effectiveType]).
  final PromptAppType appType;
  final String appName;
  final String packageName;
  final String versionName;
  final ScreenOrientation orientation;
  final Set<AppPermission> permissions;
  final StorageKind storage;

  /// Free-form idea of the app written by the user.
  final String description;
  final String themeColor;
  final UiLanguage uiLanguage;
  final TargetAi targetAi;
  final GameEngine gameEngine;
  final WebServiceMode webServiceMode;

  /// Site URL (remote wrapper) or API base URL (API client).
  final String remoteUrl;
  final SpaFramework spaFramework;
  final NativeUi nativeUi;
  final bool includeFullContract;

  bool get isIphone => platform == PromptPlatform.iphone;

  /// Project type actually generated: iPhone prompts are always Flutter.
  PromptAppType get effectiveType => isIphone ? PromptAppType.flutter : appType;

  /// Whether the generated project goes through the npm build stage.
  bool get usesNode =>
      effectiveType == PromptAppType.nodeSpa ||
      (effectiveType == PromptAppType.game && gameEngine != GameEngine.canvas);

  /// Remote URL is required for web services.
  bool get needsRemoteUrl => effectiveType == PromptAppType.webService;

  PromptConfig copyWith({
    PromptPlatform? platform,
    PromptAppType? appType,
    String? appName,
    String? packageName,
    String? versionName,
    ScreenOrientation? orientation,
    Set<AppPermission>? permissions,
    StorageKind? storage,
    String? description,
    String? themeColor,
    UiLanguage? uiLanguage,
    TargetAi? targetAi,
    GameEngine? gameEngine,
    WebServiceMode? webServiceMode,
    String? remoteUrl,
    SpaFramework? spaFramework,
    NativeUi? nativeUi,
    bool? includeFullContract,
  }) =>
      PromptConfig(
        platform: platform ?? this.platform,
        appType: appType ?? this.appType,
        appName: appName ?? this.appName,
        packageName: packageName ?? this.packageName,
        versionName: versionName ?? this.versionName,
        orientation: orientation ?? this.orientation,
        permissions: permissions ?? this.permissions,
        storage: storage ?? this.storage,
        description: description ?? this.description,
        themeColor: themeColor ?? this.themeColor,
        uiLanguage: uiLanguage ?? this.uiLanguage,
        targetAi: targetAi ?? this.targetAi,
        gameEngine: gameEngine ?? this.gameEngine,
        webServiceMode: webServiceMode ?? this.webServiceMode,
        remoteUrl: remoteUrl ?? this.remoteUrl,
        spaFramework: spaFramework ?? this.spaFramework,
        nativeUi: nativeUi ?? this.nativeUi,
        includeFullContract: includeFullContract ?? this.includeFullContract,
      );
}
