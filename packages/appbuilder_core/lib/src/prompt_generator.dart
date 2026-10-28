import 'dart:convert';

import 'agent_contract.dart';
import 'models.dart';
import 'prompt_config.dart';
import 'toolchain.dart';
import 'validators.dart';

/// Generates an exhaustive specification ("mega-prompt") for an external AI
/// model so that its answer is accepted by the AppBuilder Engine as is.
class PromptGenerator {
  const PromptGenerator();

  static const _json = JsonEncoder.withIndent('  ');

  /// Problems that must be fixed before generating a prompt.
  List<String> validate(PromptConfig c) => [
        ?Validators.appName(c.appName),
        ?Validators.packageName(c.packageName),
        ?Validators.versionName(c.versionName),
        ?Validators.hexColor(c.themeColor),
        if (c.description.trim().length < 10) 'Опишите приложение подробнее (минимум 10 символов)',
        if (c.needsRemoteUrl && !RegExp(r'^https://[^\s/]+\.[^\s]+$').hasMatch(c.remoteUrl.trim()))
          'Укажите адрес, начинающийся с https://',
      ];

  String generate(PromptConfig c) {
    final b = StringBuffer();
    final profile = _profileName(c);

    b.writeln('# Задача');
    b.writeln();
    b.writeln(c.isIphone
        ? 'Ты — senior iOS-разработчик, пишущий на Flutter. Создай полностью рабочее приложение для **iPhone** '
            '«${c.appName}» на Flutter ${Toolchain.flutter} (Dart ${Toolchain.flutterDart}). Твой ответ будет упакован в ZIP '
            'и собран в настоящее нативное приложение iOS (.ipa, Xcode на macOS) автоматическим сборщиком '
            '**AppBuilder Engine** (контракт v${Toolchain.contractVersion}) без участия человека, поэтому строго соблюдай '
            'формат ниже: любое отступление ломает сборку. Приложение должно выглядеть и вести себя как качественное '
            'приложение для iPhone, а не как перенесённое с Android.'
        : c.effectiveType.isFlutter
        ? 'Ты — senior-разработчик Flutter. Создай полностью рабочее Android-приложение «${c.appName}» на Flutter '
            '${Toolchain.flutter} (Dart ${Toolchain.flutterDart}). Твой ответ будет упакован в ZIP и собран в APK '
            'автоматическим сборщиком **AppBuilder Engine** (контракт v${Toolchain.contractVersion}) '
            'без участия человека, поэтому строго соблюдай формат ниже: любое отступление ломает сборку.'
        : 'Ты — senior-разработчик мобильных приложений. Создай полностью рабочее Android-приложение '
            '«${c.appName}». Твой ответ будет упакован в ZIP и собран в APK автоматическим сборщиком '
            '**AppBuilder Engine** (контракт v${Toolchain.contractVersion}) без участия человека, поэтому '
            'строго соблюдай формат ниже: любое отступление ломает сборку.');
    b.writeln();
    b.writeln('## Что должно делать приложение');
    b.writeln();
    b.writeln(c.description.trim());
    b.writeln();

    b.writeln('## Фиксированные параметры (не меняй их)');
    b.writeln();
    b.writeln('| Параметр | Значение |');
    b.writeln('|---|---|');
    b.writeln('| Название | ${c.appName} |');
    b.writeln(c.isIphone
        ? '| Пакет (bundle id) | `${c.packageName}` (сборщик заменит `_` на `-`) |'
        : '| Пакет (applicationId) | `${c.packageName}` |');
    b.writeln('| Версия | ${c.versionName} (versionCode 1) |');
    b.writeln('| Ориентация экрана | ${c.orientation.title} (`${c.orientation.id}`) |');
    b.writeln('| Разрешения | ${_permissionList(c)} |');
    b.writeln('| Хранение данных | ${_storageTitle(c)} |');
    b.writeln('| Язык интерфейса | ${c.uiLanguage.title} |');
    b.writeln('| Основной цвет | ${c.themeColor} |');
    final tech = PromptTech.of(c);
    b.writeln('| Язык / технология | ${tech.title} |');
    b.writeln('| Платформа | ${c.isIphone ? 'iPhone (.ipa), iOS 13 и новее, iPhone SE — Pro Max' : 'Android (APK), Android 7.0+ (API ${Toolchain.minSdk})'} |');
    b.writeln('| Тип проекта сборщика | $profile |');
    if (c.needsRemoteUrl) {
      b.writeln('| ${c.webServiceMode == WebServiceMode.remoteSite ? 'Сайт' : 'Базовый URL API'} | ${c.remoteUrl.trim()} |');
    }
    b.writeln();

    switch (c.effectiveType) {
      case PromptAppType.utility:
        _staticWeb(b, c, _utilityFiles(c), _utilityRules(c));
      case PromptAppType.webService:
        if (c.webServiceMode == WebServiceMode.remoteSite) {
          _staticWeb(b, c, _remoteFiles, _remoteRules(c));
        } else {
          _staticWeb(b, c, _apiClientFiles(c), _apiClientRules(c));
        }
      case PromptAppType.game:
        switch (c.gameEngine) {
          case GameEngine.canvas:
            _staticWeb(b, c, _canvasFiles, _canvasRules(c));
          case GameEngine.phaser:
            _nodeProject(b, c, _phaserPackage(c), _phaserFiles, _phaserRules(c));
          case GameEngine.three:
            _nodeProject(b, c, _threePackage(c), _threeFiles, _threeRules(c));
        }
      case PromptAppType.nodeSpa:
        if (c.spaFramework == SpaFramework.react) {
          _nodeProject(b, c, _reactPackage(c), _reactFiles, _reactRules(c));
        } else {
          _nodeProject(b, c, _vuePackage(c), _vueFiles, _vueRules(c));
        }
      case PromptAppType.nativeAndroid:
        _native(b, c);
      case PromptAppType.flutter:
        c.isIphone ? _iphone(b, c) : _flutter(b, c);
    }

    _forbidden(b, c);
    _answerFormat(b, c);
    _checklist(b, c);

    if (c.includeFullContract) {
      b.writeln();
      b.writeln('---');
      b.writeln();
      b.writeln('# Приложение: полный контракт AppBuilder Engine');
      b.writeln();
      b.write(buildAgentContract());
    }
    return b.toString();
  }

  // ------------------------------------------------------------ common bits

  String _profileName(PromptConfig c) {
    if (c.effectiveType == PromptAppType.nativeAndroid) return 'C1 — нативные исходники Kotlin (без Gradle-файлов)';
    if (c.isIphone) return 'D — Flutter (pubspec.yaml + lib/), сборка .ipa на macOS';
    if (c.effectiveType.isFlutter) return 'D — Flutter (pubspec.yaml + lib/), сборка APK';
    if (c.usesNode) return 'B — Node.js SPA (npm install → npm run build → WebView)';
    return 'A — статический веб (HTML/CSS/JS в WebView)';
  }

  String _permissionList(PromptConfig c) {
    final perms = _effectivePermissions(c);
    return perms.isEmpty ? 'нет' : perms.map((p) => '${p.title} (`${p.id}`)').join(', ');
  }

  Set<AppPermission> _effectivePermissions(PromptConfig c) {
    final set = {...c.permissions};
    if (c.needsRemoteUrl) set.add(AppPermission.internet);
    if (c.effectiveType.usesWebView) set.retainAll(AppPermission.webSupported);
    return set;
  }

  String _storageTitle(PromptConfig c) => switch (c.storage) {
        StorageKind.none => 'не требуется',
        StorageKind.keyValue =>
          c.effectiveType.isFlutter ? 'shared_preferences' : (c.effectiveType.isNative ? 'SharedPreferences' : 'localStorage (JSON)'),
        StorageKind.database =>
          c.effectiveType.isFlutter ? 'SQLite (sqflite)' : (c.effectiveType.isNative ? 'SQLite (SQLiteOpenHelper)' : 'IndexedDB'),
      };

  String _slug(PromptConfig c) {
    final last = c.packageName.split('.').last.toLowerCase();
    return last.isEmpty ? 'app' : last;
  }

  Map<String, Object?> _appBuilderJson(PromptConfig c, {Map<String, Object?>? web, Map<String, Object?>? android}) => {
        'appName': c.appName,
        'packageName': c.packageName,
        'versionName': c.versionName,
        'versionCode': 1,
        'orientation': c.orientation.id,
        'permissions': _effectivePermissions(c).map((p) => p.id).toList(),
        'web': ?web,
        'android': ?android,
      };

  Map<String, Object?> _webConfig(PromptConfig c, {String? outputDir, bool fullscreen = false, String? startUrl}) => {
        'outputDir': ?outputDir,
        'startUrl': startUrl ?? 'index.html',
        'fullscreen': fullscreen,
        'themeColor': c.themeColor,
        'backgroundColor': '#FFFFFF',
        'openLinksExternally': true,
      };

  void _codeBlock(StringBuffer b, String lang, String code) {
    b.writeln('```$lang');
    b.writeln(code.trimRight());
    b.writeln('```');
    b.writeln();
  }

  void _bullets(StringBuffer b, List<String> items) {
    for (final i in items) {
      b.writeln('- $i');
    }
    b.writeln();
  }

  List<String> _webRuntimeRules(PromptConfig c) => [
        'Приложение работает в Android System WebView (Chromium ≥ 100). Файлы отдаются с origin '
            '`${Toolchain.webAssetOrigin}/` — это https, поэтому доступны localStorage, IndexedDB, ES-модули, fetch локальных файлов.',
        '**Все пути относительные**: `./js/app.js`, `./css/style.css`, `fetch(\'./data.json\')`. Никаких `/app.js` и `file://`.',
        'Никаких CDN и внешних шрифтов: всё, что нужно для работы, лежит в архиве. Шрифт — системный стек '
            '(`system-ui, -apple-system, Roboto, sans-serif`).',
        'Mobile-first: `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">`, '
            'отступы `env(safe-area-inset-*)`, элементы касания ≥ 48px, без зависимости от hover.',
        'Тёмная тема через `@media (prefers-color-scheme: dark)`; основной цвет ${c.themeColor}.',
        'Несколько экранов — через hash-навигацию (`#/list`, `#/settings`) или переключение секций; кнопка «Назад» Android вызывает `history.back()`.',
        'Ошибки показывай в интерфейсе (не только в console). Не используй `window.open` — ссылки на другие сайты сами откроются в браузере.',
        'Сохранение файла пользователю: `<a href="blob:…" download="имя.ext">` (оболочка сохранит в «Загрузки»); '
            'выбор файла: `<input type="file">`.',
        'Подключи манифест: `<link rel="manifest" href="./manifest.json">`.',
      ];

  List<String> _webStorageRules(PromptConfig c) => switch (c.storage) {
        StorageKind.none => const ['Постоянное хранение не требуется — состояние живёт в памяти.'],
        StorageKind.keyValue => [
            'Храни данные в `localStorage` как JSON под ключом `${_slug(c)}:v1`; оборачивай чтение/запись в try/catch, '
                'при повреждённых данных начинай с пустого состояния.',
            'Сохраняй сразу после каждого изменения (данные должны пережить закрытие приложения).',
          ],
        StorageKind.database => [
            'Храни данные в IndexedDB (база `${_slug(c)}`, версия 1) через собственную обёртку на Promise '
                '(`openDB`, `getAll`, `put`, `delete`) без сторонних библиотек.',
            'Создавай object store в `onupgradeneeded`, используй `keyPath: "id"` и `crypto.randomUUID()` для id.',
            'Добавь экспорт всех данных в JSON-файл (blob-ссылка с `download`) и импорт через `<input type="file">`.',
          ],
      };

  List<String> _webPermissionRules(PromptConfig c) {
    final p = _effectivePermissions(c);
    return [
      if (p.contains(AppPermission.location))
        'Геолокация: `navigator.geolocation.getCurrentPosition` с `{enableHighAccuracy: true, timeout: 15000}`; обработай отказ и ошибку.',
      if (p.contains(AppPermission.camera))
        'Камера: `navigator.mediaDevices.getUserMedia({video: {facingMode: "environment"}})`; останавливай треки при уходе с экрана.',
      if (p.contains(AppPermission.microphone)) 'Микрофон: `getUserMedia({audio: true})` / MediaRecorder; обработай отказ.',
      if (p.contains(AppPermission.vibration)) 'Вибрация: `navigator.vibrate(…)`.',
      if (!p.contains(AppPermission.internet))
        'Разрешения на интернет нет: приложение полностью офлайн, никаких сетевых запросов.',
    ];
  }

  // --------------------------------------------------------------- profile A

  void _staticWeb(StringBuffer b, PromptConfig c, String tree, List<String> specific) {
    final fullscreen = c.effectiveType == PromptAppType.game;
    final remote = c.effectiveType == PromptAppType.webService && c.webServiceMode == WebServiceMode.remoteSite;
    b.writeln('## Структура ZIP-архива (строго, файлы в корне архива)');
    b.writeln();
    _codeBlock(b, '', tree);
    b.writeln('## appbuilder.json (положи в корень без изменений)');
    b.writeln();
    _codeBlock(
        b,
        'json',
        _json.convert(_appBuilderJson(c,
            web: _webConfig(c, fullscreen: fullscreen, startUrl: remote ? c.remoteUrl.trim() : null))));
    b.writeln('## manifest.json');
    b.writeln();
    _codeBlock(b, 'json', _json.convert(_webManifest(c, fullscreen: fullscreen)));
    b.writeln('Иконку сделай файлом `icon.svg` (квадрат, `viewBox="0 0 512 512"`, без внешних ссылок и текста-шрифтов) — '
        'сборщик сам превратит её в иконки Android. PNG не генерируй.');
    b.writeln();
    b.writeln('## Технические правила');
    b.writeln();
    _bullets(b, [..._webRuntimeRules(c), ...specific]);
    b.writeln('## Хранение данных');
    b.writeln();
    _bullets(b, _webStorageRules(c));
    final perms = _webPermissionRules(c);
    if (perms.isNotEmpty) {
      b.writeln('## Разрешения и API устройства');
      b.writeln();
      _bullets(b, perms);
    }
  }

  Map<String, Object?> _webManifest(PromptConfig c, {required bool fullscreen}) => {
        'name': c.appName,
        'short_name': c.appName.length > 12 ? c.appName.substring(0, 12) : c.appName,
        'start_url': './index.html',
        'display': fullscreen ? 'fullscreen' : 'standalone',
        'orientation': switch (c.orientation) {
          ScreenOrientation.portrait => 'portrait',
          ScreenOrientation.landscape => 'landscape',
          ScreenOrientation.sensor => 'any',
        },
        'theme_color': c.themeColor,
        'background_color': '#FFFFFF',
        'icons': [
          {'src': './icon.svg', 'sizes': 'any', 'type': 'image/svg+xml', 'purpose': 'any'},
        ],
      };

  String _utilityFiles(PromptConfig c) => [
        'index.html',
        'manifest.json',
        'icon.svg',
        'appbuilder.json',
        'css/style.css',
        'js/app.js          ← точка входа, <script type="module" src="./js/app.js">',
        if (c.storage != StorageKind.none) 'js/storage.js      ← слой хранения',
        'js/ui.js           ← отрисовка интерфейса (при необходимости — дополнительные модули в js/)',
      ].join('\n');

  List<String> _utilityRules(PromptConfig c) => const [
        'Только HTML5 + CSS3 + современный JavaScript (ES2022, ES-модули). Без фреймворков, npm и этапа сборки.',
        'Вся логика реальная и полностью рабочая: вычисления, валидация ввода, обработка граничных случаев (пустой ввод, деление на ноль, длинные строки).',
        'Интерфейс в стиле Material 3: карточки, FAB/кнопки, понятные состояния (пусто, ошибка, успех).',
      ];

  static const _remoteFiles = 'index.html         ← офлайн-страница: показывается, если сайт не загрузился\n'
      'manifest.json\n'
      'icon.svg\n'
      'appbuilder.json\n'
      'css/style.css';

  List<String> _remoteRules(PromptConfig c) => [
        'Оболочка сразу открывает сайт `${c.remoteUrl.trim()}` (поле `web.startUrl`). Свой код сайта не пиши.',
        '`index.html` — офлайн-экран «Нет подключения к интернету» с кнопкой «Повторить», '
            'которая выполняет `location.href = "${c.remoteUrl.trim()}"`. Его показывает оболочка при ошибке загрузки.',
        'Ссылки на другие домены откроются в системном браузере, переходы внутри сайта — в приложении.',
      ];

  String _apiClientFiles(PromptConfig c) => [
        'index.html',
        'manifest.json',
        'icon.svg',
        'appbuilder.json',
        'css/style.css',
        'js/app.js          ← точка входа и роутинг по hash',
        'js/api.js          ← все запросы к API',
        if (c.storage != StorageKind.none) 'js/storage.js      ← кэш и настройки',
        'js/views/…         ← экраны',
      ].join('\n');

  List<String> _apiClientRules(PromptConfig c) => [
        'Работай с реальным API `${c.remoteUrl.trim()}` через `fetch` + `AbortController` (таймаут 15 с). Никаких моков и фейковых данных.',
        'Запросы идут с origin `${Toolchain.webAssetOrigin}`: API обязан отдавать CORS-заголовки. '
            'Если известно, что этот API не поддерживает CORS, прямо напиши об этом в ответе и предложи вариант «Обёртка сайта».',
        'Если API требует ключ или токен — сделай экран настроек, где пользователь вводит его сам; храни в localStorage. Не вставляй выдуманные ключи.',
        'Состояния: загрузка (скелетон/спиннер), ошибка с кнопкой «Повторить», пустой результат, офлайн (`navigator.onLine`).',
        'Последние успешные ответы кэшируй в хранилище и показывай без сети с пометкой «данные от <время>».',
      ];

  static const _canvasFiles = 'index.html\n'
      'manifest.json\n'
      'icon.svg\n'
      'appbuilder.json\n'
      'css/style.css\n'
      'js/main.js         ← точка входа, <script type="module" src="./js/main.js">\n'
      'js/game.js         ← игровой цикл и логика\n'
      'js/input.js        ← касания / мышь / клавиатура\n'
      'js/audio.js        ← звуки через Web Audio API (генерация осцилляторами)';

  List<String> _canvasRules(PromptConfig c) => [
        'Чистый Canvas 2D без библиотек. Игровой цикл на `requestAnimationFrame` с delta time (ограничь dt 50 мс).',
        'Canvas на весь экран, учитывай `devicePixelRatio`, пересчитывай размеры на `resize`; логическое разрешение фиксируй и масштабируй.',
        'Управление через Pointer Events (касания и мышь); `touch-action: none`, без скролла и масштабирования страницы.',
        'Графику рисуй кодом (фигуры, градиенты) или inline-SVG — внешние изображения не нужны.',
        'Звук — Web Audio API, разблокировка по первому касанию.',
        'Пауза при `visibilitychange`; рекорд сохраняй в localStorage.',
        'Экраны: старт, игра, пауза, game over с рестартом.',
      ];

  // --------------------------------------------------------------- profile B

  void _nodeProject(StringBuffer b, PromptConfig c, Map<String, Object?> packageJson, String tree, List<String> specific) {
    final fullscreen = c.effectiveType == PromptAppType.game;
    b.writeln('## Структура ZIP-архива (строго, файлы в корне архива)');
    b.writeln();
    _codeBlock(b, '', tree);
    b.writeln('Сборщик выполнит `npm install` и `npm run build`, затем упакует папку `dist/` в WebView. '
        'Не добавляй `node_modules/`, `dist/` и lock-файлы, не меняй версии ниже.');
    b.writeln();
    b.writeln('## package.json (используй эти зависимости и версии; можно добавить только реально нужные пакеты)');
    b.writeln();
    _codeBlock(b, 'json', _json.convert(packageJson));
    b.writeln('## vite.config.js');
    b.writeln();
    _codeBlock(b, 'js', _viteConfig(c));
    b.writeln('## appbuilder.json (положи в корень без изменений)');
    b.writeln();
    _codeBlock(b, 'json', _json.convert(_appBuilderJson(c, web: _webConfig(c, outputDir: 'dist', fullscreen: fullscreen))));
    b.writeln('## public/manifest.json');
    b.writeln();
    _codeBlock(b, 'json', _json.convert(_webManifest(c, fullscreen: fullscreen)));
    b.writeln('Иконка — `public/icon.svg` (квадрат, `viewBox="0 0 512 512"`). PNG не генерируй.');
    b.writeln();
    b.writeln('## Технические правила');
    b.writeln();
    _bullets(b, [
      'Пиши на JavaScript (ESM, JSX/SFC), **без TypeScript** — меньше точек отказа при сборке.',
      '`index.html` в корне проекта; точка входа подключается так: `<script type="module" src="./src/main.${c.spaFramework == SpaFramework.react && c.effectiveType == PromptAppType.nodeSpa ? 'jsx' : 'js'}"></script>`; '
          'манифест: `<link rel="manifest" href="./manifest.json">` (файл лежит в public/).',
      '`base: \'./\'` в vite.config.js обязателен — итоговые пути должны быть относительными.',
      'Ассеты импортируй из `src/` (`import url from \'./assets/x.svg\'`) или клади в `public/` и ссылайся относительно (`./sounds/x.mp3`).',
      ..._webRuntimeRules(c).where((r) => !r.contains('<link rel="manifest"')),
      ...specific,
    ]);
    b.writeln('## Хранение данных');
    b.writeln();
    _bullets(b, _webStorageRules(c));
    final perms = _webPermissionRules(c);
    if (perms.isNotEmpty) {
      b.writeln('## Разрешения и API устройства');
      b.writeln();
      _bullets(b, perms);
    }
  }

  String _viteConfig(PromptConfig c) {
    final isReact = c.effectiveType == PromptAppType.nodeSpa && c.spaFramework == SpaFramework.react;
    final isVue = c.effectiveType == PromptAppType.nodeSpa && c.spaFramework == SpaFramework.vue;
    final tailwind = c.effectiveType == PromptAppType.nodeSpa;
    final imports = [
      "import { defineConfig } from 'vite';",
      if (isReact) "import react from '@vitejs/plugin-react';",
      if (isVue) "import vue from '@vitejs/plugin-vue';",
      if (tailwind) "import tailwindcss from '@tailwindcss/vite';",
    ];
    final plugins = [if (isReact) 'react()', if (isVue) 'vue()', if (tailwind) 'tailwindcss()'];
    return '''
${imports.join('\n')}

export default defineConfig({
  base: './',
  plugins: [${plugins.join(', ')}],
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    chunkSizeWarningLimit: 4096,
  },
});
''';
  }

  Map<String, Object?> _basePackage(PromptConfig c, Map<String, String> deps, Map<String, String> devDeps) => {
        'name': _slug(c),
        'private': true,
        'version': c.versionName,
        'type': 'module',
        'scripts': {'dev': 'vite', 'build': 'vite build', 'preview': 'vite preview'},
        'dependencies': deps,
        'devDependencies': {'vite': Toolchain.webStack['vite']!, ...devDeps},
      };

  Map<String, Object?> _reactPackage(PromptConfig c) => _basePackage(c, {
        'react': Toolchain.webStack['react']!,
        'react-dom': Toolchain.webStack['react-dom']!,
        'react-router-dom': Toolchain.webStack['react-router-dom']!,
      }, {
        '@vitejs/plugin-react': Toolchain.webStack['@vitejs/plugin-react']!,
        'tailwindcss': Toolchain.webStack['tailwindcss']!,
        '@tailwindcss/vite': Toolchain.webStack['@tailwindcss/vite']!,
      });

  static const _reactFiles = 'package.json\n'
      'vite.config.js\n'
      'index.html\n'
      'appbuilder.json\n'
      'public/manifest.json\n'
      'public/icon.svg\n'
      'src/main.jsx        ← createRoot + HashRouter\n'
      'src/App.jsx\n'
      'src/index.css       ← @import "tailwindcss";\n'
      'src/components/…\n'
      'src/pages/…\n'
      'src/lib/storage.js  ← слой хранения (если нужен)';

  List<String> _reactRules(PromptConfig c) => const [
        'React 19 с функциональными компонентами и хуками; состояние — useState/useReducer + Context, без Redux.',
        'Роутинг только `HashRouter` (или `createHashRouter`) из react-router-dom.',
        'Стили — Tailwind CSS v4 (`@import "tailwindcss";` в src/index.css, плагин `@tailwindcss/vite`, без tailwind.config.js и PostCSS).',
      ];

  Map<String, Object?> _vuePackage(PromptConfig c) => _basePackage(c, {
        'vue': Toolchain.webStack['vue']!,
        'vue-router': Toolchain.webStack['vue-router']!,
      }, {
        '@vitejs/plugin-vue': Toolchain.webStack['@vitejs/plugin-vue']!,
        'tailwindcss': Toolchain.webStack['tailwindcss']!,
        '@tailwindcss/vite': Toolchain.webStack['@tailwindcss/vite']!,
      });

  static const _vueFiles = 'package.json\n'
      'vite.config.js\n'
      'index.html\n'
      'appbuilder.json\n'
      'public/manifest.json\n'
      'public/icon.svg\n'
      'src/main.js         ← createApp + router\n'
      'src/App.vue\n'
      'src/router.js       ← createWebHashHistory()\n'
      'src/style.css       ← @import "tailwindcss";\n'
      'src/views/…\n'
      'src/components/…\n'
      'src/lib/storage.js  ← слой хранения (если нужен)';

  List<String> _vueRules(PromptConfig c) => const [
        'Vue 3, Composition API и `<script setup>`; состояние — reactive/ref + composables, без Pinia.',
        'Роутер: `createRouter({ history: createWebHashHistory(), routes })`.',
        'Стили — Tailwind CSS v4 (`@import "tailwindcss";`, плагин `@tailwindcss/vite`, без tailwind.config.js и PostCSS).',
      ];

  Map<String, Object?> _phaserPackage(PromptConfig c) =>
      _basePackage(c, {'phaser': Toolchain.webStack['phaser']!}, const {});

  static const _phaserFiles = 'package.json\n'
      'vite.config.js\n'
      'index.html\n'
      'appbuilder.json\n'
      'public/manifest.json\n'
      'public/icon.svg\n'
      'src/main.js              ← new Phaser.Game(config)\n'
      'src/scenes/BootScene.js  ← генерация текстур кодом\n'
      'src/scenes/MenuScene.js\n'
      'src/scenes/GameScene.js\n'
      'src/scenes/GameOverScene.js';

  List<String> _phaserRules(PromptConfig c) {
    final portrait = c.orientation != ScreenOrientation.landscape;
    return [
      'Phaser 3 (`import Phaser from \'phaser\'`), `type: Phaser.AUTO`, '
          '`scale: { mode: Phaser.Scale.FIT, autoCenter: Phaser.Scale.CENTER_BOTH, width: ${portrait ? 720 : 1280}, height: ${portrait ? 1280 : 720} }`.',
      'Текстуры создавай в BootScene кодом: `this.make.graphics()` → `generateTexture(key, w, h)`. Внешних картинок нет.',
      'Управление касаниями (`this.input.on(\'pointerdown\', …)`), без клавиатуры как единственного способа.',
      'Звуки — необязательны; если нужны, генерируй через Web Audio API.',
      'Рекорд сохраняй в localStorage; пауза при `this.game.events.on(\'hidden\')`.',
    ];
  }

  Map<String, Object?> _threePackage(PromptConfig c) =>
      _basePackage(c, {'three': Toolchain.webStack['three']!}, const {});

  static const _threeFiles = 'package.json\n'
      'vite.config.js\n'
      'index.html\n'
      'appbuilder.json\n'
      'public/manifest.json\n'
      'public/icon.svg\n'
      'src/main.js       ← renderer, сцена, цикл\n'
      'src/world.js      ← объекты сцены (процедурная геометрия)\n'
      'src/controls.js   ← сенсорное управление\n'
      'src/ui.js         ← HUD поверх canvas (HTML/CSS)\n'
      'src/style.css';

  List<String> _threeRules(PromptConfig c) => const [
        'Three.js: `import * as THREE from \'three\'`, дополнения — `import { … } from \'three/addons/…\'`.',
        '`renderer.setPixelRatio(Math.min(devicePixelRatio, 2))`, пересчёт камеры и размера на `resize`, `renderer.setAnimationLoop`.',
        'Геометрия и материалы — процедурные (BoxGeometry, SphereGeometry, MeshStandardMaterial, свет). Без загрузки моделей и текстур из сети.',
        'Сенсорное управление через Pointer Events (виртуальный джойстик / свайпы / тапы); `touch-action: none`.',
        'Следи за производительностью мобильных GPU: до ~50k треугольников, без тяжёлых пост-эффектов.',
      ];

  // --------------------------------------------------------------- profile C

  void _native(StringBuffer b, PromptConfig c) {
    final pkgPath = c.packageName.replaceAll('.', '/');
    final compose = c.nativeUi == NativeUi.compose;
    final perms = _effectivePermissions(c);

    b.writeln('## Структура ZIP-архива (строго, файлы в корне архива)');
    b.writeln();
    _codeBlock(b, '', [
      'appbuilder.json',
      'app/src/main/AndroidManifest.xml',
      'app/src/main/java/$pkgPath/MainActivity.kt',
      if (compose) 'app/src/main/java/$pkgPath/ui/theme/Theme.kt',
      if (compose) 'app/src/main/java/$pkgPath/ui/…            ← экраны (Composable)',
      if (!compose) 'app/src/main/res/layout/activity_main.xml',
      if (!compose) 'app/src/main/res/layout/…                 ← остальные разметки',
      if (c.storage != StorageKind.none) 'app/src/main/java/$pkgPath/data/…          ← хранение данных',
      'app/src/main/java/$pkgPath/…                ← остальные классы',
      'app/src/main/res/values/strings.xml',
      'app/src/main/res/values/colors.xml',
      'app/src/main/res/values/themes.xml',
    ].join('\n'));
    b.writeln('**Не создавай** `build.gradle(.kts)`, `settings.gradle(.kts)`, `gradle.properties`, `gradlew`, папку `gradle/` и иконки '
        '`mipmap/ic_launcher*` — их генерирует сборщик (AGP ${Toolchain.androidGradlePlugin}, Kotlin ${Toolchain.kotlin}, '
        'compileSdk ${Toolchain.compileSdk}, minSdk ${Toolchain.minSdk}, Java ${Toolchain.java}, '
        '`namespace = "${c.packageName}"`, ViewBinding включён, R8 выключен).');
    b.writeln();
    b.writeln('## appbuilder.json (положи в корень)');
    b.writeln();
    _codeBlock(b, 'json', _json.convert(_appBuilderJson(c, android: {'compose': compose, 'dependencies': <String>[]})));
    b.writeln('В `android.dependencies` добавляй библиотеку, только если она действительно нужна и ты уверен в существовании '
        'указанной версии (формат `group:artifact:version`, Google Maven / Maven Central). Иначе используй Android SDK.');
    b.writeln();
    b.writeln('## AndroidManifest.xml (основа)');
    b.writeln();
    final permissionXml = perms.expand((p) => p.manifestPermissions).map((m) => '    ${m.toXml()}').join('\n');
    _codeBlock(b, 'xml', '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
${permissionXml.isEmpty ? '' : '$permissionXml\n'}
    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.App">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:screenOrientation="${c.orientation.androidValue}"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>''');
    b.writeln('Атрибут `package` у `<manifest>` не указывай. `strings.xml` обязан содержать `<string name="app_name">${_xmlEscape(c.appName)}</string>`.');
    b.writeln();

    b.writeln('## Доступные библиотеки (уже подключены сборщиком)');
    b.writeln();
    _bullets(b, [
      ...Toolchain.nativeBaseDependencies.map((d) => '`$d`'),
      if (compose) 'Compose BOM `${Toolchain.composeBom}`: ${Toolchain.composeDependencies.map((d) => '`$d`').join(', ')}',
    ]);

    b.writeln('## Технические правила');
    b.writeln();
    _bullets(b, [
      'Язык — Kotlin ${Toolchain.kotlin}. Все классы в пакете `${c.packageName}` (и подпакетах). `R` импортируется как `${c.packageName}.R`.',
      'minSdk ${Toolchain.minSdk}: API новее Android 7.0 вызывай под проверкой `Build.VERSION.SDK_INT`.',
      if (compose) ...[
        '`class MainActivity : ComponentActivity()`, в `onCreate`: `enableEdgeToEdge()` и `setContent { AppTheme { … } }`.',
        'Тема: `res/values/themes.xml` → `<style name="Theme.App" parent="android:Theme.Material.Light.NoActionBar" />`; '
            'цвета Compose — `lightColorScheme/darkColorScheme` с primary = ${c.themeColor}, `isSystemInDarkTheme()`.',
        'Material 3 (`androidx.compose.material3.*`): Scaffold + TopAppBar (`@OptIn(ExperimentalMaterial3Api::class)`), отступы `innerPadding`.',
        'Иконки — только из material-icons-core: `Icons.Filled.Add`, `Delete`, `Edit`, `Search`, `Settings`, `Home`, `Favorite`, `Star`, '
            '`Info`, `Close`, `Check`, `Refresh`, `Share`, `MoreVert`, `Menu`, `Person`, `Place`, `DateRange`, `Notifications`, `Warning`, '
            '`PlayArrow`, `Lock`, `Email`, `Phone`, `ShoppingCart`, `ThumbUp`, `AccountCircle`, `Done`, `LocationOn`, `Clear`, '
            '`Icons.AutoMirrored.Filled.ArrowBack`, `Icons.AutoMirrored.Filled.Send`, `Icons.AutoMirrored.Filled.List`. material-icons-extended не подключён.',
        'Состояние — `ViewModel` + `StateFlow`, в UI `collectAsStateWithLifecycle()`; `viewModel()` из lifecycle-viewmodel-compose.',
      ] else ...[
        '`class MainActivity : AppCompatActivity()`, ViewBinding (`ActivityMainBinding.inflate(layoutInflater)`).',
        'Тема: `<style name="Theme.App" parent="Theme.Material3.DayNight.NoActionBar">` с `colorPrimary` = ${c.themeColor}; '
            'компоненты Material (MaterialToolbar, MaterialButton, TextInputLayout, RecyclerView, FloatingActionButton).',
        'Edge-to-edge: `WindowCompat.setDecorFitsSystemWindows(window, false)` + `ViewCompat.setOnApplyWindowInsetsListener` для отступов.',
        'Списки — RecyclerView + ListAdapter + DiffUtil. Фоновая работа — корутины (`lifecycleScope`, `Dispatchers.IO`).',
      ],
      'Кнопка «Назад» — `onBackPressedDispatcher.addCallback(…)`, не `onBackPressed()`.',
      'Без kapt/KSP: Room, Hilt, Dagger недоступны. Без NDK, Firebase и Google Play Services (если они не добавлены в appbuilder.json).',
    ]);

    b.writeln('## Хранение данных');
    b.writeln();
    _bullets(b, switch (c.storage) {
      StorageKind.none => const ['Постоянное хранение не требуется.'],
      StorageKind.keyValue => const [
          '`SharedPreferences` (`context.getSharedPreferences("app", MODE_PRIVATE)`), сложные структуры — JSON через `org.json`.',
          'Сохраняй сразу при изменении (`edit { … }` из core-ktx).',
        ],
      StorageKind.database => [
          'SQLite через собственный `SQLiteOpenHelper` (БД `${_slug(c)}.db`, версия 1, `onCreate`/`onUpgrade`).',
          'Репозиторий с реальными CRUD-операциями, запросы на `Dispatchers.IO`, параметризованные запросы (`?`).',
        ],
    });

    final runtime = <String>[
      if (perms.contains(AppPermission.camera))
        'Камера: `registerForActivityResult(ActivityResultContracts.TakePicturePreview())` (или RequestPermission + своя логика); запрос CAMERA в рантайме.',
      if (perms.contains(AppPermission.location))
        'Геолокация: `LocationManager` (GPS_PROVIDER / NETWORK_PROVIDER), запрос ACCESS_FINE_LOCATION через `ActivityResultContracts.RequestMultiplePermissions()`.',
      if (perms.contains(AppPermission.microphone)) 'Микрофон: `MediaRecorder` / `AudioRecord`, запрос RECORD_AUDIO в рантайме.',
      if (perms.contains(AppPermission.notifications))
        'Уведомления: `NotificationChannel` (API 26+), `NotificationCompat`, запрос POST_NOTIFICATIONS на API 33+.',
      if (perms.contains(AppPermission.vibration)) 'Вибрация: `Vibrator`/`VibratorManager` (API 31+) с проверкой версии.',
      if (perms.contains(AppPermission.storage))
        'Файлы: Storage Access Framework (`ActivityResultContracts.CreateDocument` / `OpenDocument`), без прямого доступа к /sdcard.',
      'Каждый отказ в разрешении обрабатывай: объясни пользователю и не падай.',
    ];
    b.writeln('## Разрешения и API устройства');
    b.writeln();
    _bullets(b, runtime);
  }

  /// Dart package name for pubspec.yaml (`com.example.shop_list` → `shop_list`).
  String _dartName(PromptConfig c) {
    final last = c.packageName.split('.').last.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    return RegExp(r'^[a-z]').hasMatch(last) ? last : 'app_$last';
  }

  /// pub.dev packages the selected permissions and storage need.
  Map<String, String> _flutterPackages(PromptConfig c) {
    final perms = _effectivePermissions(c);
    final v = Toolchain.flutterPackages;
    return {
      'provider': v['provider']!,
      if (c.storage == StorageKind.keyValue) 'shared_preferences': v['shared_preferences']!,
      if (c.storage == StorageKind.database) ...{'sqflite': v['sqflite']!, 'path': v['path']!},
      if (perms.contains(AppPermission.camera) || perms.contains(AppPermission.storage)) 'image_picker': v['image_picker']!,
      if (perms.contains(AppPermission.location)) 'geolocator': v['geolocator']!,
      if (perms.contains(AppPermission.internet) || perms.contains(AppPermission.wifi)) ...{
        'http': v['http']!,
        'connectivity_plus': v['connectivity_plus']!,
      },
      if (perms.contains(AppPermission.wifi)) 'network_info_plus': v['network_info_plus']!,
      if (c.isIphone) ...{'url_launcher': v['url_launcher']!, 'share_plus': v['share_plus']!, 'path_provider': v['path_provider']!},
      if (c.isIphone && perms.contains(AppPermission.storage)) 'file_picker': v['file_picker']!,
    };
  }

  void _flutterStructure(StringBuffer b, PromptConfig c) {
    b.writeln('## Структура ZIP-архива (строго, файлы в корне архива)');
    b.writeln();
    _codeBlock(b, '', [
      'appbuilder.json',
      'pubspec.yaml',
      'analysis_options.yaml',
      'lib/main.dart                 ← MaterialApp, тема, провайдеры',
      'lib/models/…                  ← модели данных',
      if (c.storage != StorageKind.none) 'lib/data/…                    ← хранение данных (репозиторий)',
      'lib/services/…                ← работа с сетью и устройством',
      'lib/state/…                   ← ChangeNotifier-контроллеры (provider)',
      'lib/screens/…                 ← экраны',
      'lib/widgets/…                 ← переиспользуемые виджеты',
    ].join('\n'));
    b.writeln('**Не создавай** папки `android/`, `ios/`, `web/`, файлы `pubspec.lock` и иконки: сборщик сам выполнит '
        '`flutter create`, пропишет ${c.isIphone ? 'bundle id' : 'пакет'} `${c.packageName}`, название, версию, '
        'разрешения и иконку.');
    b.writeln();
  }

  void _pubspec(StringBuffer b, PromptConfig c, Map<String, String> packages) {
    b.writeln('## pubspec.yaml (основа)');
    b.writeln();
    _codeBlock(b, 'yaml', [
      'name: ${_dartName(c)}',
      'description: ${c.appName}',
      "publish_to: 'none'",
      'version: ${c.versionName}+1',
      '',
      'environment:',
      '  sdk: ^${Toolchain.flutterDart}',
      '',
      'dependencies:',
      '  flutter:',
      '    sdk: flutter',
      for (final e in packages.entries) '  ${e.key}: ${e.value}',
      '',
      'dev_dependencies:',
      '  flutter_test:',
      '    sdk: flutter',
      '  flutter_lints: ^6.0.0',
      '',
      'flutter:',
      '  uses-material-design: true',
    ].join('\n'));
    b.writeln('Другие пакеты добавляй, только если они действительно нужны, поддерживают '
        '${c.isIphone ? '**iOS**' : '**Android**'} и ты уверен, что указанная версия существует на pub.dev. '
        'Проверенные версии: ${Toolchain.flutterPackages.entries.map((e) => '`${e.key}: ${e.value}`').join(', ')}.');
    b.writeln();
    b.writeln('`analysis_options.yaml`: `include: package:flutter_lints/flutter.yaml`.');
    b.writeln();
  }

  List<String> _flutterStorageRules(PromptConfig c) => switch (c.storage) {
        StorageKind.none => const ['Постоянное хранение не требуется.'],
        StorageKind.keyValue => const [
            '`shared_preferences` (`SharedPreferencesAsync`), сложные структуры — JSON (`dart:convert`).',
            'Сохраняй сразу при изменении, загружай при старте до показа данных (индикатор загрузки, пока читаются данные).',
          ],
        StorageKind.database => [
            'SQLite через `sqflite`: база `${_slug(c)}.db` в `getDatabasesPath()` (`path.join`), версия 1, `onCreate`/`onUpgrade`.',
            'Репозиторий с реальными CRUD-операциями, параметризованные запросы (`whereArgs`), транзакции для пакетных изменений.',
          ],
      };

  // ------------------------------------------------------- profile D: Android

  void _flutter(StringBuffer b, PromptConfig c) {
    final name = _dartName(c);
    final perms = _effectivePermissions(c);
    _flutterStructure(b, c);
    b.writeln('## appbuilder.json (положи в корень)');
    b.writeln();
    _codeBlock(b, 'json', _json.convert(_appBuilderJson(c, web: {'themeColor': c.themeColor, 'backgroundColor': '#FFFFFF'})));
    _pubspec(b, c, _flutterPackages(c));

    b.writeln('## Технические правила');
    b.writeln();
    _bullets(b, [
      'Flutter ${Toolchain.flutter}, Dart ${Toolchain.flutterDart}, null safety, Material 3 (`useMaterial3: true`), '
          '`ColorScheme.fromSeed(seedColor: Color(0xFF${c.themeColor.substring(1)}))`, светлая и тёмная тема (`themeMode: ThemeMode.system`).',
      'Состояние — `provider` (`ChangeNotifierProvider` / `MultiProvider`, `context.watch` / `context.read`).',
      'Импорты своих файлов — `package:$name/…`. Код без устаревших API (без `WillPopScope` → `PopScope`, `withOpacity` → `withValues`).',
      'Интерфейс адаптивный: `SafeArea`, прокрутка длинных экранов, без фиксированных размеров под один телефон; '
          'системная кнопка «Назад» Android закрывает диалоги и экраны.',
      'Android ${Toolchain.minSdk}+ (Android 7.0): файлы — через `path_provider`, без `dart:html`.',
      'Язык интерфейса: ${c.uiLanguage.title}. Тексты — прямо в виджетах (без генерации l10n).',
      if (c.orientation != ScreenOrientation.sensor)
        'Ориентацию сборщик задаёт в манифесте; дополнительно вызови `SystemChrome.setPreferredOrientations` в `main()`.',
    ]);

    b.writeln('## Хранение данных');
    b.writeln();
    _bullets(b, _flutterStorageRules(c));

    final runtime = <String>[
      if (perms.contains(AppPermission.camera)) 'Камера и фото: `image_picker` (`ImagePicker().pickImage(source: ImageSource.camera)`).',
      if (perms.contains(AppPermission.location))
        'Геолокация: `geolocator` — `isLocationServiceEnabled`, `checkPermission`/`requestPermission`, затем `getCurrentPosition`.',
      if (perms.contains(AppPermission.internet))
        'Сеть: `http` с таймаутами (`.timeout`) и обработкой `SocketException`/`TimeoutException` (сообщение и кнопка «Повторить»); '
            'тип подключения — `connectivity_plus`.',
      if (perms.contains(AppPermission.wifi)) ...[
        'Wi-Fi: `network_info_plus` — `getWifiIP()`, `getWifiSubmask()`, `getWifiGatewayIP()`; `getWifiName()` (SSID) требует '
            'разрешения на геолокацию и включённой геолокации, иначе вернёт null — обрабатывай null.',
        'Локальная сеть: `dart:io` `Socket.connect(host, port, timeout: …)` и `http` к IP-адресам устройств; сканируй подсеть '
            'пачками по 32–64 адреса, отменяй сканирование при уходе с экрана.',
      ],
      'Разрешения уже перечислены в appbuilder.json — сборщик добавит их в AndroidManifest.xml. '
          'Отказ пользователя обрабатывай: объясни и не падай.',
    ];
    b.writeln('## Разрешения и API устройства');
    b.writeln();
    _bullets(b, runtime);
  }

  // -------------------------------------------------------- profile D: iPhone

  /// Info.plist usage descriptions the selected permissions need (the AI
  /// rewrites the texts for the actual app).
  Map<String, Object> _iosInfoPlist(PromptConfig c) {
    final p = _effectivePermissions(c);
    return {
      if (p.contains(AppPermission.camera)) 'NSCameraUsageDescription': 'Камера нужна, чтобы <зачем именно>.',
      if (p.contains(AppPermission.camera) || p.contains(AppPermission.storage)) ...{
        'NSPhotoLibraryUsageDescription': 'Доступ к фото нужен, чтобы <зачем именно>.',
        'NSPhotoLibraryAddUsageDescription': 'Приложение сохраняет <что> в «Фото».',
      },
      if (p.contains(AppPermission.location) || p.contains(AppPermission.wifi))
        'NSLocationWhenInUseUsageDescription': 'Геопозиция нужна, чтобы <зачем именно>.',
      if (p.contains(AppPermission.microphone)) 'NSMicrophoneUsageDescription': 'Микрофон нужен, чтобы <зачем именно>.',
      if (p.contains(AppPermission.wifi)) 'NSLocalNetworkUsageDescription': 'Доступ к локальной сети нужен, чтобы <зачем именно>.',
      if (p.contains(AppPermission.storage)) ...{'UIFileSharingEnabled': true, 'LSSupportsOpeningDocumentsInPlace': true},
    };
  }

  void _iphone(StringBuffer b, PromptConfig c) {
    final name = _dartName(c);
    final p = _effectivePermissions(c);
    final plist = _iosInfoPlist(c);
    _flutterStructure(b, c);

    b.writeln('## appbuilder.json (положи в корень)');
    b.writeln();
    _codeBlock(
        b,
        'json',
        _json.convert({
          ..._appBuilderJson(c, web: {'themeColor': c.themeColor, 'backgroundColor': '#FFFFFF'}),
          if (plist.isNotEmpty) 'ios': {'infoPlist': plist},
        }));
    if (plist.isNotEmpty) {
      b.writeln('`ios.infoPlist` попадёт в Info.plist приложения. **Перепиши каждый текст** `<…>` конкретно под это '
          'приложение (${c.uiLanguage.title}, 1 предложение: что и зачем) — iOS показывает его в системном окне запроса '
          'доступа. Без описания iOS аварийно закрывает приложение при первом обращении к камере, фото, геопозиции, '
          'микрофону или локальной сети. Добавляй только ключи, которые реально используются.');
      b.writeln();
    }
    _pubspec(b, c, _flutterPackages(c));

    b.writeln('## Как проект станет .ipa (учитывай ограничения)');
    b.writeln();
    _bullets(b, [
      'Сборщик на macOS выполнит `flutter create --platforms=ios`, пропишет bundle id, название (CFBundleDisplayName), '
          'версию, ориентацию, иконку и ключи `ios.infoPlist`, затем `flutter build ios --release --no-codesign`. '
          'Получится настоящее нативное приложение iOS (Flutter + Xcode), не веб-страница.',
      'Минимальная версия — iOS 13. Плагины подключаются через CocoaPods автоматически — бери только пакеты с поддержкой iOS.',
      '.ipa не подписан: пользователь устанавливает его через Sideloadly под своим Apple ID (бесплатный аккаунт — '
          'приложение работает 7 дней, затем переустанавливается). Поэтому **недоступно** всё, что требует платного '
          'аккаунта Apple Developer или особых entitlements: push-уведомления (APNs/Firebase Messaging), iCloud, '
          'Sign in with Apple, Apple Pay, HealthKit, App Groups, виджеты и расширения, NFC-запись, Hotspot Configuration, '
          'multicast-сеть. Не используй их и не предлагай.',
      'Нельзя писать нативный Swift/Objective-C код, AppDelegate, Podfile, entitlements — только Dart и плагины pub.dev.',
      'Не используй `permission_handler`: на iOS он требует правки Podfile (макросы `PERMISSION_…`), без них всегда '
          'возвращает «запрещено». Запрашивай доступ средствами самих плагинов (`Geolocator.requestPermission()`, '
          '`MobileScanner`, `ImagePicker`).',
    ]);

    b.writeln('## Интерфейс в стиле iPhone');
    b.writeln();
    _bullets(b, [
      'Flutter ${Toolchain.flutter}, Dart ${Toolchain.flutterDart}, null safety. Material 3 (`useMaterial3: true`, '
          '`ColorScheme.fromSeed(seedColor: Color(0xFF${c.themeColor.substring(1)}))`) с iOS-поведением: светлая и тёмная '
          'тема по системе (`themeMode: ThemeMode.system`), шрифт системный (San Francisco) — не подключай свои шрифты без нужды.',
      'Адаптивные элементы: `Switch.adaptive`, `Slider.adaptive`, `CircularProgressIndicator.adaptive`, '
          '`showAdaptiveDialog` + `AlertDialog.adaptive`, `TextButton`; меню действий — `CupertinoActionSheet` '
          '(`showCupertinoModalPopup`), выбор даты — `CupertinoDatePicker`.',
      'Навигация: `NavigationBar` внизу для 2–5 разделов, переходы `Navigator.push(MaterialPageRoute(...))` — на iOS '
          'они анимируются как в iPhone и закрываются свайпом от левого края. Аппаратной кнопки «Назад» нет: на каждом '
          'вложенном экране — кнопка назад в AppBar (появляется сама), не блокируй свайп без причины '
          '(`PopScope` — только для подтверждения потери несохранённых данных).',
      '`SafeArea` / `MediaQuery.paddingOf` для чёлки, Dynamic Island и полосы «домой»; содержимое не прячется под ними. '
          'Крупные заголовки — `SliverAppBar.large` на главных экранах-списках.',
      'Клавиатура: `TextInputAction.next/done`, закрытие тапом вне поля (`FocusScope.of(context).unfocus()`) и '
          'прокруткой (`keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`); поля не перекрываются клавиатурой.',
      'Размеры: от iPhone SE (375×667) до Pro Max (440×956), элементы касания ≥ 44 pt; поддержка крупного шрифта '
          '(Dynamic Type) — без фиксированной высоты текстовых блоков и без переполнения при `textScaler` 1.5.',
      'Отклик: `HapticFeedback.selectionClick()` / `lightImpact()` на важные действия; анимации 200–300 мс.',
      'Приложение никогда не закрывает себя (`exit(0)` запрещён правилами Apple; `SystemNavigator.pop()` на iOS не работает).',
      'Импорты своих файлов — `package:$name/…`. Без устаревших API (`WillPopScope` → `PopScope`, `withOpacity` → `withValues`). '
          'Тяжёлые вычисления — `Isolate.run`, длинные списки — `ListView.builder`.',
      'Язык интерфейса: ${c.uiLanguage.title}. Тексты — прямо в виджетах (без генерации l10n).',
      if (c.orientation != ScreenOrientation.sensor)
        'Ориентацию сборщик задаёт в Info.plist; дополнительно вызови `SystemChrome.setPreferredOrientations` в `main()`.',
    ]);

    b.writeln('## Жизненный цикл и фоновая работа на iOS');
    b.writeln();
    _bullets(b, const [
      'Через несколько секунд после сворачивания iOS приостанавливает приложение: таймеры, сокеты, загрузки и `Future` '
          'замирают, а система может завершить его без предупреждения. Фоновых сервисов, как на Android, нет.',
      'Долгие операции (сканирование сети, синхронизация, загрузки) выполняй, пока приложение на экране; '
          '`WidgetsBindingObserver.didChangeAppLifecycleState`: при `paused` останавливай работу и сохраняй состояние, '
          'при `resumed` — обновляй данные и продолжай.',
      'Всё важное сохраняй сразу, а не при закрытии: события закрытия на iOS не гарантированы.',
    ]);

    b.writeln('## Хранение данных');
    b.writeln();
    _bullets(b, [
      ..._flutterStorageRules(c),
      'Файлы — только в песочнице приложения: `getApplicationDocumentsDirectory()` (данные пользователя, попадают в '
          'резервную копию), `getApplicationCacheDirectory()` (временное). Общих папок вроде «Загрузок» на iOS нет.',
      'Экспорт файла — через меню «Поделиться»: `SharePlus.instance.share(ShareParams(files: [XFile(path)], '
          'sharePositionOrigin: …))` (сохранить в «Файлы», AirDrop, мессенджеры); `sharePositionOrigin` обязателен на iPad.',
    ]);

    final network = <String>[
      if (p.contains(AppPermission.internet) || p.contains(AppPermission.wifi)) ...[
        'HTTP: `package:http` с `.timeout(const Duration(seconds: 15))`; обрабатывай `SocketException`, `TimeoutException`, '
            '`HandshakeException`, коды ответа ≠ 2xx — понятное сообщение и кнопка «Повторить». Предпочитай HTTPS.',
        'Тип подключения: `Connectivity().checkConnectivity()` возвращает `List<ConnectivityResult>` (wifi / mobile / '
            'none), изменения — `onConnectivityChanged`. Это тип интерфейса, а не наличие интернета: доступность '
            'проверяй реальным запросом.',
      ],
      if (p.contains(AppPermission.wifi)) ...[
        '**Локальная сеть (iOS 14+).** При первом подключении к устройству в локальной сети iOS показывает окно '
            '«Приложение хочет находить устройства в локальной сети» с текстом `NSLocalNetworkUsageDescription`. '
            'Вызывай первое обращение осознанно (по кнопке «Найти устройства»), а не при запуске. Пока доступ не дан '
            'или если он запрещён, подключения падают с `SocketException` (No route to host / errno 65): API проверки '
            'статуса нет — распознавай отказ по ошибке и показывай инструкцию: «Настройки → Конфиденциальность и '
            'безопасность → Локальная сеть → включите ${c.appName}».',
        'Параметры Wi-Fi: `NetworkInfo()` из `network_info_plus` — `getWifiIP()`, `getWifiSubmask()`, '
            '`getWifiGatewayIP()`, `getWifiBroadcast()` работают без дополнительных прав. Из IP и маски вычисляй подсеть.',
        'Название сети (SSID) и BSSID: `getWifiName()` / `getWifiBSSID()` на iOS требуют разрешения на геопозицию '
            '**и** entitlement «Access WiFi Information», которого нет у неподписанного .ipa — на установленном через '
            'Sideloadly приложении они обычно возвращают null. Обязательно обрабатывай null («Название сети недоступно '
            'на iPhone») и не делай функции зависимыми от SSID.',
        'Поиск устройств: multicast и broadcast (UDP 255.255.255.255, SSDP, ONVIF WS-Discovery, mDNS без списка служб) '
            'на iOS требуют entitlement `com.apple.developer.networking.multicast` — **недоступен**. Ищи устройства '
            'unicast-перебором подсети: `Socket.connect(ip, port, timeout: const Duration(milliseconds: 500))` пачками '
            'по 32–64 адреса (не 254 одновременно — у iOS ограничено число сокетов), с прогрессом, кнопкой «Стоп» и '
            'закрытием каждого сокета (`destroy()`). Затем проверяй найденные адреса HTTP-запросом.',
        'Bonjour (если без него нельзя): все типы служб перечисли в `ios.infoPlist` → `NSBonjourServices` '
            '(например `["_http._tcp"]`), иначе iOS блокирует поиск.',
        'HTTP к устройствам в локальной сети разрешён: сборщик добавит в Info.plist `NSAppTransportSecurity → '
            'NSAllowsLocalNetworking`. Для HTTP к внешним сайтам — только HTTPS.',
        'Программно включить/выключить Wi-Fi, получить список сетей или подключиться к сети на iOS **нельзя** '
            '(публичного API нет). Вместо этого — инструкция и кнопка «Открыть настройки»: '
            '`launchUrl(Uri.parse(\'app-settings:\'))` (`url_launcher`).',
        'В iOS Simulator параметры Wi-Fi возвращают null — интерфейс должен оставаться рабочим.',
      ],
      if (p.contains(AppPermission.location))
        'Геопозиция: `geolocator` — `isLocationServiceEnabled()`, `checkPermission()`/`requestPermission()` в момент, '
            'когда она нужна; `deniedForever` → объяснение и `Geolocator.openAppSettings()`. Фоновая геолокация не нужна.',
      if (p.contains(AppPermission.camera))
        'Камера: фото — `image_picker` (`ImageSource.camera`); QR и штрихкоды — `mobile_scanner: '
            '${Toolchain.flutterPackages['mobile_scanner']}` (`MobileScanner` + `MobileScannerController`, остановка при '
            'уходе с экрана и в `paused`). Отказ в доступе → объяснение и кнопка «Открыть настройки».',
      if (p.contains(AppPermission.storage))
        'Фото и файлы: выбор из галереи — `image_picker` (`ImageSource.gallery`), документы — `file_picker`; '
            '`UIFileSharingEnabled` делает папку Documents видимой в приложении «Файлы».',
      if (p.contains(AppPermission.microphone))
        'Микрофон: описание `NSMicrophoneUsageDescription` уже в `ios.infoPlist`; используй пакет записи только с поддержкой iOS.',
      if (p.contains(AppPermission.vibration)) 'Вибрация: `HapticFeedback` (`lightImpact`, `mediumImpact`, `heavyImpact`, `vibrate`).',
      if (p.contains(AppPermission.notifications))
        'Уведомления: push недоступны (нужен платный аккаунт). Показывай события внутри приложения (баннер, '
            '`SnackBar`, бейдж на вкладке) — не обещай уведомления при закрытом приложении.',
      'Версия приложения и модель устройства (экран «О приложении»): `package_info_plus`, `device_info_plus` — если нужны.',
      'Каждый отказ в доступе обрабатывай: объясни, что не будет работать, и дай кнопку «Открыть настройки»; приложение не падает.',
    ];
    b.writeln('## Сеть, Wi-Fi и возможности устройства на iPhone');
    b.writeln();
    _bullets(b, network);
  }

  // ------------------------------------------------------------ final parts

  void _forbidden(StringBuffer b, PromptConfig c) {
    b.writeln('## Запрещено');
    b.writeln();
    _bullets(b, [
      'Заглушки, моки, фейковые данные, «TODO», «// остальной код», имитация загрузки через таймеры вместо реальной логики.',
      'Папка-обёртка верхнего уровня в архиве; `node_modules/`, `dist/`, `build/`, `.git/`, ключи подписи.',
      if (c.effectiveType.usesWebView) 'Абсолютные пути (`/app.js`), `file://`, CDN-ссылки, `http://`.',
      if (c.effectiveType.isNative) 'Gradle-файлы, `local.properties`, иконки `ic_launcher`, атрибут `package` в манифесте.',
      if (c.effectiveType.isFlutter)
        'Папки `android/`, `ios/`, `build/`, `.dart_tool/`, файл `pubspec.lock`, иконки и нативный код — их создаёт сборщик.',
      if (c.isIphone) ...[
        '`permission_handler`, Firebase Messaging и другие push-уведомления, iCloud, плагины без поддержки iOS.',
        'Android-приёмы на iPhone: аппаратная кнопка «Назад», фоновые сервисы, broadcast/multicast-поиск, '
            'включение Wi-Fi из приложения, `exit(0)`.',
      ],
      'Выдуманные API-ключи и адреса. Если нужен ключ — сделай поле ввода в настройках.',
      'Сокращение файлов: каждый файл выводится целиком.',
    ]);
  }

  void _answerFormat(StringBuffer b, PromptConfig c) {
    b.writeln('## Формат ответа');
    b.writeln();
    _bullets(b, [
      'Сначала коротко (3–6 строк) опиши архитектуру.',
      'Затем дерево файлов.',
      'Затем каждый файл полностью: заголовок `### путь/к/файлу` и блок кода с содержимым.',
      'В конце — команда упаковки, чтобы файлы оказались в корне архива: `cd ${_slug(c)} && zip -r ../${_slug(c)}.zip .`',
      switch (c.targetAi) {
        TargetAi.chatgpt => 'Если у тебя есть инструмент выполнения Python (Code Interpreter) — создай все файлы, '
            'упакуй их в ZIP (файлы в корне архива) и дай ссылку на скачивание, а код всё равно выведи в ответе.',
        TargetAi.claude => 'Если доступен инструмент выполнения кода или создания файлов — создай файлы и ZIP-архив '
            '(файлы в корне), а код всё равно выведи полностью в ответе.',
        TargetAi.deepseek => 'Выведи все файлы полностью, не сокращая: пользователь соберёт ZIP вручную. '
            'Если ответ не помещается — остановись на границе файла и продолжи с этого файла после слова «дальше».',
        TargetAi.other => 'Если умеешь создавать файлы — сформируй ZIP-архив (файлы в корне), иначе выведи все файлы полностью.',
      },
    ]);
  }

  void _checklist(StringBuffer b, PromptConfig c) {
    b.writeln('## Самопроверка перед отправкой ответа');
    b.writeln();
    final items = [
      'Все файлы из структуры созданы, ни один не сокращён.',
      '`appbuilder.json` совпадает с приведённым выше (пакет `${c.packageName}`).',
      if (c.effectiveType.usesWebView) ...[
        'Все ссылки в HTML/CSS/JS относительные (`./…`), внешних CDN нет.',
        'Манифест подключён, `icon.svg` существует.',
      ],
      if (c.usesNode) ...[
        '`npm run build` создаёт `dist/index.html`; `base: \'./\'`; роутинг через hash.',
        'Все импортируемые пакеты перечислены в package.json.',
      ],
      if (c.effectiveType.isNative) ...[
        'Все `.kt` файлы начинаются с `package ${c.packageName}…`, импорты существуют в подключённых библиотеках.',
        'Каждый ресурс, на который ссылается код (`R.layout`, `R.string`, `R.id`, `@style/Theme.App`), объявлен.',
        'Код компилируется Kotlin ${Toolchain.kotlin} без ошибок: нет устаревших/удалённых API, все `@OptIn` проставлены.',
      ],
      if (c.effectiveType.isFlutter) ...[
        '`pubspec.yaml`: `name: ${_dartName(c)}`, `version: ${c.versionName}+1`, все импортируемые пакеты перечислены.',
        'Импорты своих файлов — `package:${_dartName(c)}/…`; код проходит `flutter analyze` без ошибок на Flutter ${Toolchain.flutter}.',
        if (c.isIphone)
          'Нет `dart:html` и пакетов без поддержки iOS; файлы — через `path_provider`.'
        else
          'Нет `dart:html` и пакетов без поддержки Android; файлы — через `path_provider`.',
      ],
      if (c.isIphone) ...[
        'В `ios.infoPlist` все тексты `<…>` заменены конкретными объяснениями, лишних ключей нет.',
        'Интерфейс проверен мысленно на iPhone SE и Pro Max: ничего не перекрыто чёлкой, клавиатурой и полосой «домой», '
            'на каждом вложенном экране есть путь назад.',
        'Отказ в любом доступе, null вместо названия Wi-Fi и сворачивание приложения во время работы не ломают его.',
      ],
      'Данные действительно сохраняются и восстанавливаются после перезапуска.',
      'Каждая кнопка и экран выполняют реальное действие.',
    ];
    for (final i in items) {
      b.writeln('- [ ] $i');
    }
  }

  static String _xmlEscape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll("'", "\\'");
}
