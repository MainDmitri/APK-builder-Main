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
    b.writeln('Ты — senior-разработчик мобильных приложений. Создай полностью рабочее Android-приложение '
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
    b.writeln('| Пакет (applicationId) | `${c.packageName}` |');
    b.writeln('| Версия | ${c.versionName} (versionCode 1) |');
    b.writeln('| Ориентация экрана | ${c.orientation.title} (`${c.orientation.id}`) |');
    b.writeln('| Разрешения | ${_permissionList(c)} |');
    b.writeln('| Хранение данных | ${_storageTitle(c)} |');
    b.writeln('| Язык интерфейса | ${c.uiLanguage.title} |');
    b.writeln('| Основной цвет | ${c.themeColor} |');
    b.writeln('| Тип проекта сборщика | $profile |');
    if (c.needsRemoteUrl) {
      b.writeln('| ${c.webServiceMode == WebServiceMode.remoteSite ? 'Сайт' : 'Базовый URL API'} | ${c.remoteUrl.trim()} |');
    }
    b.writeln();

    switch (c.appType) {
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
    if (c.appType == PromptAppType.nativeAndroid) return 'C1 — нативные исходники Kotlin (без Gradle-файлов)';
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
    if (!c.appType.isNative) set.retainAll(AppPermission.webSupported);
    return set;
  }

  String _storageTitle(PromptConfig c) => switch ((c.storage, c.appType.isNative)) {
        (StorageKind.none, _) => 'не требуется',
        (StorageKind.keyValue, false) => 'localStorage (JSON)',
        (StorageKind.keyValue, true) => 'SharedPreferences',
        (StorageKind.database, false) => 'IndexedDB',
        (StorageKind.database, true) => 'SQLite (SQLiteOpenHelper)',
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
    final fullscreen = c.appType == PromptAppType.game;
    final remote = c.appType == PromptAppType.webService && c.webServiceMode == WebServiceMode.remoteSite;
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
    final fullscreen = c.appType == PromptAppType.game;
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
      '`index.html` в корне проекта; точка входа подключается так: `<script type="module" src="./src/main.${c.spaFramework == SpaFramework.react && c.appType == PromptAppType.nodeSpa ? 'jsx' : 'js'}"></script>`; '
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
    final isReact = c.appType == PromptAppType.nodeSpa && c.spaFramework == SpaFramework.react;
    final isVue = c.appType == PromptAppType.nodeSpa && c.spaFramework == SpaFramework.vue;
    final tailwind = c.appType == PromptAppType.nodeSpa;
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

  // ------------------------------------------------------------ final parts

  void _forbidden(StringBuffer b, PromptConfig c) {
    b.writeln('## Запрещено');
    b.writeln();
    _bullets(b, [
      'Заглушки, моки, фейковые данные, «TODO», «// остальной код», имитация загрузки через таймеры вместо реальной логики.',
      'Папка-обёртка верхнего уровня в архиве; `node_modules/`, `dist/`, `build/`, `.git/`, ключи подписи.',
      if (!c.appType.isNative) 'Абсолютные пути (`/app.js`), `file://`, CDN-ссылки, `http://`.',
      if (c.appType.isNative) 'Gradle-файлы, `local.properties`, иконки `ic_launcher`, атрибут `package` в манифесте.',
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
      if (!c.appType.isNative) ...[
        'Все ссылки в HTML/CSS/JS относительные (`./…`), внешних CDN нет.',
        'Манифест подключён, `icon.svg` существует.',
      ],
      if (c.usesNode) ...[
        '`npm run build` создаёт `dist/index.html`; `base: \'./\'`; роутинг через hash.',
        'Все импортируемые пакеты перечислены в package.json.',
      ],
      if (c.appType.isNative) ...[
        'Все `.kt` файлы начинаются с `package ${c.packageName}…`, импорты существуют в подключённых библиотеках.',
        'Каждый ресурс, на который ссылается код (`R.layout`, `R.string`, `R.id`, `@style/Theme.App`), объявлен.',
        'Код компилируется Kotlin ${Toolchain.kotlin} без ошибок: нет устаревших/удалённых API, все `@OptIn` проставлены.',
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
