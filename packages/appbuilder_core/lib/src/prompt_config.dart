import 'models.dart';

enum PromptAppType {
  utility('utility', 'Инструмент / Утилита', 'Калькулятор, конвертер, заметки, трекер привычек'),
  webService('web-service', 'Веб-сервис / PWA-клиент', 'Клиент для сайта, дашборд, клиент REST API'),
  game('game', '2D Canvas / WebGL игра', 'Phaser, Three.js, чистый Canvas'),
  nativeAndroid('native', 'Нативный Android-проект', 'Камера, датчики, сервисы на Kotlin'),
  nodeSpa('node-spa', 'Node.js SPA', 'React или Vue + Vite + Tailwind'),
  flutter('flutter', 'Flutter: Android + iPhone', 'Нативное приложение на Dart, один код для обеих платформ');

  const PromptAppType(this.id, this.title, this.examples);

  final String id;
  final String title;
  final String examples;

  bool get isNative => this == PromptAppType.nativeAndroid;
  bool get isFlutter => this == PromptAppType.flutter;

  /// HTML/JS projects running in the WebView shell.
  bool get usesWebView => !isNative && !isFlutter;
}

/// Language / technology the AI writes the app in (first choice of the
/// prompt wizard). Maps onto [PromptAppType] and [SpaFramework].
enum PromptTech {
  javascript('HTML + JavaScript', 'Без сборки: утилиты, клиенты сайтов и API, игры на Canvas / Phaser / Three.js',
      iphone: true),
  react('React (JavaScript)', 'React 19 + Vite + Tailwind CSS: сложные интерфейсы, много экранов', iphone: true),
  vue('Vue (JavaScript)', 'Vue 3 + Vite + Tailwind CSS: сложные интерфейсы, много экранов', iphone: true),
  flutter('Flutter (Dart)', 'Нативное приложение: один код, быстрый интерфейс, плагины', iphone: true),
  kotlin('Kotlin', 'Нативный Android: Jetpack Compose или XML-разметка, полный доступ к Android API', iphone: false);

  const PromptTech(this.title, this.description, {required this.iphone});

  final String title;
  final String description;

  /// Can also be built as an .ipa for iPhone.
  final bool iphone;

  String get platforms => iphone ? 'Android и iPhone' : 'только Android';

  static PromptTech of(PromptConfig c) => switch (c.appType) {
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

  /// Whether the generated project goes through the npm build stage.
  bool get usesNode =>
      appType == PromptAppType.nodeSpa ||
      (appType == PromptAppType.game && gameEngine != GameEngine.canvas);

  /// Remote URL is required for web services.
  bool get needsRemoteUrl => appType == PromptAppType.webService;

  PromptConfig copyWith({
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
