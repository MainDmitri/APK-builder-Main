import 'models.dart';
import 'toolchain.dart';

/// Builds the machine-readable contract (`/docs/agent-contract.md`) that tells
/// external AI models how to prepare code for the AppBuilder Engine.
String buildAgentContract() {
  final permissionRows = AppPermission.values.map((p) {
    final android = p.manifestPermissions
        .map((m) => m.maxSdkVersion == null ? m.name.split('.').last : '${m.name.split('.').last} (≤ API ${m.maxSdkVersion})')
        .join(', ');
    final web = switch (p) {
      AppPermission.internet => '`fetch`, внешние ресурсы, удалённый `startUrl`',
      AppPermission.storage => 'не нужно для `<input type=file>` и скачиваний на Android 10+; совместимость со старыми версиями',
      AppPermission.location => '`navigator.geolocation`',
      AppPermission.camera => '`getUserMedia({video})`',
      AppPermission.microphone => '`getUserMedia({audio})`',
      AppPermission.vibration => '`navigator.vibrate()`',
      AppPermission.notifications => 'не поддерживается WebView (только профиль C)',
    };
    return '| `${p.id}` | $android | $web |';
  }).join('\n');

  final nativeDeps = Toolchain.nativeBaseDependencies.map((d) => '- `$d`').join('\n');
  final composeDeps = Toolchain.composeDependencies.map((d) => '- `$d`').join('\n');

  return '''
# AppBuilder Engine — AI Agent Contract v${Toolchain.contractVersion}

> Машиночитаемая спецификация для ИИ-моделей (ChatGPT, Claude, DeepSeek, Gemini и др.),
> которые пишут код для автоматической сборки в APK движком **AppBuilder Engine**.
> Следуй правилам буквально: архив, подготовленный по контракту, превращается
> в подписанный APK без ручных правок.

## 0. Кратко

1. Результат работы — **один ZIP-архив**. Файлы проекта лежат **прямо в корне** архива,
   без обёртки верхнего уровня (`my-app/…` — ошибка).
2. В корне может лежать `appbuilder.json` — название, пакет, версия, ориентация, разрешения.
3. Тип проекта определяется автоматически, по приоритету:

| Приоритет | Признак в корне архива | Профиль |
|---|---|---|
| 1 | `package.json` со скриптом `build` | **B** — Node.js SPA (двухэтапная сборка) |
| 2 | `index.html` | **A** — статический веб (HTML/CSS/JS) |
| 3 | `settings.gradle(.kts)`, `AndroidManifest.xml`, `*.kt`, `*.java` | **C** — нативный Android |

4. В веб-коде все ссылки **относительные**: `./app.js`, `./css/style.css` (не `/app.js`).
5. Офлайн-приложение не грузит ничего из CDN — все библиотеки лежат в архиве или ставятся через npm.
6. Не клади в архив: `node_modules/`, `.git/`, keystore-файлы (`.jks`, `.keystore`), `local.properties`,
   собранные APK, секреты и `.env` с ключами.

## 1. Окружение сборки

| Компонент | Версия |
|---|---|
| Node.js | ${Toolchain.nodeMajor} LTS, npm, yarn и pnpm через corepack |
| JDK | ${Toolchain.java} |
| Gradle | ${Toolchain.gradle} |
| Android Gradle Plugin | ${Toolchain.androidGradlePlugin} |
| Kotlin | ${Toolchain.kotlin} |
| compileSdk / targetSdk | ${Toolchain.compileSdk} / ${Toolchain.targetSdk} |
| minSdk | ${Toolchain.minSdk} (Android 7.0) |
| Build-Tools | ${Toolchain.buildTools} (aapt2, zipalign, apksigner) |
| Подпись | APK Signature Scheme v1 + v2 + v3 |

Во время сборки есть доступ к npm registry, Google Maven и Maven Central.
Лимиты: установка зависимостей — 15 мин, `npm run build` — 15 мин, Gradle — 30 мин.

## 2. Требования к ZIP-архиву

- Формат ZIP (deflate или store), имена файлов в UTF-8, размер до 200 МБ, не более 20 000 файлов.
- Корень архива = корень проекта.

```
✅ правильно               ❌ неправильно
index.html                 my-app/
app.js                     my-app/index.html
manifest.json              my-app/app.js
appbuilder.json
```

- Если всё же есть единственная папка верхнего уровня, движок использует её как корень и выдаёт
  предупреждение. Не рассчитывай на это.
- Символические ссылки игнорируются. Пустые папки не нужны.
- Текстовые файлы — UTF-8, переводы строк любые.

## 3. appbuilder.json (необязательный, рекомендуется)

```json
{
  "appName": "Мои заметки",
  "packageName": "com.example.notes",
  "versionName": "1.0.0",
  "versionCode": 1,
  "orientation": "portrait",
  "permissions": ["internet", "storage"],
  "web": {
    "outputDir": "dist",
    "startUrl": "index.html",
    "fullscreen": false,
    "themeColor": "#1565C0",
    "backgroundColor": "#FFFFFF",
    "openLinksExternally": true
  },
  "android": {
    "compose": true,
    "dependencies": ["io.coil-kt:coil-compose:2.7.0"]
  }
}
```

| Поле | Тип | Описание |
|---|---|---|
| `appName` | string | Название под иконкой (до 50 символов) |
| `packageName` | string | applicationId, напр. `com.example.app`: ≥ 2 сегмента, латиница/цифры/`_`, сегмент начинается с буквы, без ключевых слов Java/Kotlin |
| `versionName` | string | Версия для пользователя, `1.0.0` |
| `versionCode` | int | Целое ≥ 1, растёт с каждым релизом |
| `orientation` | string | `portrait` \\| `landscape` \\| `sensor` |
| `permissions` | string[] | Идентификаторы из таблицы ниже |
| `web.outputDir` | string | Папка результата `npm run build` (профиль B), если отличается от стандартной |
| `web.startUrl` | string | Стартовая страница: относительный путь (`index.html`) или `https://…` для обёртки сайта |
| `web.fullscreen` | bool | Скрыть системные панели (игры) |
| `web.themeColor` | `#RRGGBB` | Цвет статус-бара и фона иконки |
| `web.backgroundColor` | `#RRGGBB` | Фон окна и сплэш-экрана |
| `web.openLinksExternally` | bool | Ссылки на другие домены открывать в браузере (по умолчанию `true`) |
| `android.compose` | bool | Подключить Jetpack Compose (по умолчанию — автоопределение по импортам `androidx.compose`) |
| `android.dependencies` | string[] | Доп. зависимости `group:artifact:version` (профиль C1) |

Приоритет значений: настройки сборки в UI/API → `appbuilder.json` → `manifest.json` → `package.json` → значения по умолчанию.

Разрешения:

| id | Android-разрешения | Что включает в вебе |
|---|---|---|
$permissionRows

## 4. Профиль A — статический веб (HTML / CSS / JS)

```
index.html              ← обязателен, в корне
manifest.json           ← рекомендуется (Web App Manifest)
icon.svg | icon-512.png ← иконка приложения (рекомендуется)
css/style.css
js/app.js
assets/…                ← изображения, звуки, шрифты, json
appbuilder.json         ← рекомендуется
```

### 4.1 Среда выполнения

- Файлы упаковываются в `assets/www/` APK и открываются в Android System WebView (Chromium)
  по адресу **`${Toolchain.webAssetOrigin}/`** через `WebViewAssetLoader`.
  Это постоянный защищённый (`https`) origin: работают `localStorage`, `sessionStorage`, IndexedDB,
  Cache API, ES-модули (`<script type="module">`), `fetch()` локальных файлов, WebAssembly, Service Worker.
- Данные `localStorage` / IndexedDB сохраняются между запусками и удаляются только вместе с данными приложения.
- **Только относительные пути**: `<script src="./js/app.js">`, `fetch('./data/items.json')`, `url(../img/bg.png)`.
  Абсолютные пути (`/app.js`) и `file://` запрещены контрактом.
- Маршрутизация SPA — через hash (`#/settings`). Неизвестные пути без расширения отдают `index.html`.
- Кнопка «Назад» Android выполняет `history.back()`; на первой странице закрывает приложение.
- Без CDN, если приложение должно работать офлайн. Внешние ресурсы требуют разрешения `internet`.
- Запросы к чужим API идут с origin `${Toolchain.webAssetOrigin}` — сервер API должен разрешать CORS
  (`Access-Control-Allow-Origin: *` или этот origin). Только `https://` (http заблокирован Android).
- Ссылки на другие домены открываются в браузере; `tel:`, `mailto:`, `geo:`, `intent:` — в системных приложениях.
- Обёртка сайта: `"web": {"startUrl": "https://example.com/"}` — WebView откроет сайт
  (локальные файлы архива всё равно нужны: минимум `index.html`, напр. с сообщением об ошибке сети).

### 4.2 Возможности оболочки

| Функция | Как использовать |
|---|---|
| Выбор файлов | `<input type="file" accept="image/*" multiple>` — системный диалог |
| Сохранение файла | `<a href="blob:…" download="notes.json">` или `data:`-URL → файл в «Загрузки» |
| Сохранение из JS | `window.AppBuilderAndroid?.saveFile(base64, "report.csv", "text/csv")` → `true/false` (только для локального origin) |
| Геолокация | `navigator.geolocation.getCurrentPosition(...)` + разрешение `location` |
| Камера / микрофон | `navigator.mediaDevices.getUserMedia(...)` + `camera` / `microphone` |
| Вибрация | `navigator.vibrate(200)` + `vibration` |
| Диалоги | `alert`, `confirm`, `prompt` работают |
| Полный экран | `"web": {"fullscreen": true}` или `"display": "fullscreen"` в manifest.json |

Не поддерживаются: Web Notifications и Push API, Web Bluetooth/USB/NFC, Payment Request, всплывающие окна
`window.open` (ссылка откроется в браузере), фоновая синхронизация.

### 4.3 manifest.json

```json
{
  "name": "Мои заметки",
  "short_name": "Заметки",
  "start_url": "./index.html",
  "display": "standalone",
  "orientation": "portrait",
  "theme_color": "#1565C0",
  "background_color": "#FFFFFF",
  "icons": [
    { "src": "./icon.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any" },
    { "src": "./icons/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

| Поле | Использование движком |
|---|---|
| `name` / `short_name` | Название приложения (если не задано в appbuilder.json) |
| `start_url` | Стартовая страница (относительный путь) |
| `display` | `fullscreen` скрывает системные панели; `standalone`, `minimal-ui`, `browser` — обычный режим |
| `orientation` | `portrait*` → portrait, `landscape*` → landscape, `any`/`natural` → sensor |
| `theme_color` | Статус-бар и фон адаптивной иконки |
| `background_color` | Фон окна и сплэш-экрана |
| `icons` | Самая крупная PNG / WebP / JPEG / SVG → иконки mdpi…xxxhdpi и adaptive icon. Нет иконки — генерируется буква на `theme_color` |

Подключение: `<link rel="manifest" href="./manifest.json">` в `<head>` (или файл `manifest.json` в корне).
ИИ не может сгенерировать PNG — используй **SVG-иконку** (`icon.svg`, viewBox квадратный, 512×512).

## 5. Профиль B — Node.js SPA (React, Vue, Svelte, Vite, Phaser, Three.js …)

```
package.json            ← обязателен, со скриптом "build"
package-lock.json | pnpm-lock.yaml | yarn.lock   ← необязательно
vite.config.js
index.html
src/…
public/manifest.json    ← копируется в результат сборки
public/icon.svg
appbuilder.json
```

### 5.1 Конвейер (two-stage pipeline)

1. Удаляется `node_modules/` из архива.
2. Менеджер пакетов: поле `packageManager` (`pnpm@…`, `yarn@…`) → lock-файл → npm.
3. Установка: `npm ci` (есть package-lock.json) или `npm install`, `yarn install`, `pnpm install`.
   Устанавливаются и `devDependencies` (NODE_ENV не равен production).
4. `npm run build` (или `yarn run build` / `pnpm run build`). Переменные: `PUBLIC_URL=.`, `BROWSER=none`,
   `NEXT_TELEMETRY_DISABLED=1`.
5. Поиск папки с `index.html`: `web.outputDir` → стандартная папка фреймворка
   (Vite/Vue/Astro/Parcel → `dist`, CRA → `build`, Next.js → `out`, Angular → `dist/<проект>/browser`,
   Nuxt → `.output/public`, SvelteKit → `build`) → `dist`, `build`, `out`, `www`.
6. Результат упаковывается по правилам профиля A.

### 5.2 Правила

- `scripts.build` обязателен и создаёт **только статические файлы** (без SSR и Node-сервера).
- Все зависимости перечислены в `package.json` с версиями. Без `postinstall`, требующих Python,
  компиляторов C++ или глобальных утилит. Без `.env` с секретами.
- Относительная база:
  - Vite: `base: './'` в `vite.config.js`;
  - Create React App: `"homepage": "."` в package.json;
  - Next.js: `output: 'export'`, `images: { unoptimized: true }`, `trailingSlash: true`;
  - Angular: `"baseHref": "./"` и `withHashLocation()`;
  - SvelteKit: `@sveltejs/adapter-static`, `paths: { relative: true }`.
- Роутер — только hash-режим: React Router `createHashRouter` / `HashRouter`, Vue Router `createWebHashHistory()`.
- Проверенные версии: `vite ^8`, `react ^19`, `react-dom ^19`, `@vitejs/plugin-react ^6`, `vue ^3.5`,
  `@vitejs/plugin-vue ^6`, `tailwindcss ^4` + `@tailwindcss/vite ^4` (в CSS: `@import "tailwindcss";`),
  `phaser ^3.90`, `three ^0.186`.
- Шрифты и иконки — npm-пакеты или файлы в `public/`, не CDN.

## 6. Профиль C — нативный Android

### 6.1 C1: исходники без Gradle (рекомендуется для ИИ)

```
appbuilder.json                                    ← packageName, appName, версия
app/src/main/AndroidManifest.xml
app/src/main/java/com/example/app/MainActivity.kt  ← пакет = packageName
app/src/main/java/com/example/app/…                ← .kt и/или .java
app/src/main/res/values/strings.xml                ← <string name="app_name">
app/src/main/res/values/themes.xml
app/src/main/res/layout/…                          ← для View-интерфейса
app/src/main/assets/…                              ← необязательно
```

Движок сам создаёт `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`:
AGP ${Toolchain.androidGradlePlugin}, Kotlin ${Toolchain.kotlin}, compileSdk ${Toolchain.compileSdk}, minSdk ${Toolchain.minSdk},
Java ${Toolchain.java}, `namespace` = пакет исходников, ViewBinding включён, R8 выключен.
**Не создавай** `build.gradle`, `settings.gradle`, `gradlew`, `gradle/`.

AndroidManifest.xml:

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <application
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:theme="@style/Theme.App"
        android:supportsRtl="true">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

- Без атрибута `package` у `<manifest>` (пакет = `namespace`).
- Иконки `@mipmap/ic_launcher` и `@mipmap/ic_launcher_round` **генерирует движок** — не создавай их.
- Разрешения из настроек сборки, которых нет в манифесте, движок добавит сам.
- Тема: для `AppCompatActivity` и View — родитель `Theme.Material3.DayNight.NoActionBar`;
  для Compose и `ComponentActivity` — `android:Theme.Material.Light.NoActionBar`.

Зависимости, подключённые всегда:

$nativeDeps

Jetpack Compose (подключается, если в .kt есть `import androidx.compose…` или `"android": {"compose": true}`),
BOM `${Toolchain.composeBom}`:

$composeDeps

Дополнительные библиотеки — только через `appbuilder.json → android.dependencies`
(из Google Maven или Maven Central, совместимые с compileSdk ${Toolchain.compileSdk}).

Ограничения C1:
- Без kapt/KSP: Room-компилятор, Hilt, Dagger, Moshi-codegen недоступны. Для БД — `SQLiteOpenHelper`,
  для настроек — `SharedPreferences`, для DI — вручную.
- Без NDK/C++, Firebase (`google-services.json`) и product flavors.
- targetSdk ${Toolchain.targetSdk}: окно edge-to-edge — используй `enableEdgeToEdge()` и отступы
  (`Modifier.safeDrawingPadding()` / `ViewCompat.setOnApplyWindowInsetsListener`).
- Кнопка «Назад» — через `onBackPressedDispatcher` (не `onBackPressed`).
- Опасные разрешения запрашивай в рантайме: `registerForActivityResult(ActivityResultContracts.RequestPermission())`.

### 6.2 C2: полный Gradle-проект

- `settings.gradle(.kts)` в корне, модуль приложения с `com.android.application` (обычно `app/`).
- Либо полный Gradle Wrapper (`gradlew` + `gradle/wrapper/gradle-wrapper.jar` + `gradle-wrapper.properties`),
  либо без него — тогда используется Gradle ${Toolchain.gradle} движка и нужен совместимый AGP (рекомендуется ${Toolchain.androidGradlePlugin}).
- Репозитории: `google()`, `mavenCentral()`.
- Без `signingConfigs` для release, без `local.properties`. Проверки `lintVital*` движок отключает.
- Собирается `assembleRelease`, берётся APK модуля приложения из `build/outputs/apk/release/`.
- Название, пакет и версия берутся из самого проекта.

## 7. Подпись и выдача

1. `gradle assembleRelease` → неподписанный release-APK.
2. `zipalign -p -f 4`.
3. `apksigner sign` со схемами v1 + v2 + v3:
   - **Debug Key** — постоянный debug-ключ движка (`androiddebugkey`);
   - **Production Keystore** — `.jks` / `.keystore` / `.p12`, загруженный пользователем вместе с паролями
     `storePassword`, `keyAlias`, `keyPassword` (проверяются `keytool` до сборки).
4. `apksigner verify` → файл `<appName>-<versionName>.apk`.

Ключи никогда не кладутся в архив проекта.

## 8. Чек-лист самопроверки для ИИ

- [ ] Все файлы в корне ZIP, без папки-обёртки; нет `node_modules/`, `.git/`, ключей.
- [ ] Есть `appbuilder.json` с корректным `packageName` и `appName`.
- [ ] Профиль A: `index.html` в корне; все пути относительные (`./`); нет CDN в офлайн-режиме.
- [ ] Профиль B: `package.json` со `scripts.build`; относительная база (`base: './'`); hash-роутер; сборка даёт `index.html`.
- [ ] Профиль C1: нет Gradle-файлов; `AndroidManifest.xml` без `package`, с `.MainActivity` + `exported="true"` + LAUNCHER;
      пакет исходников = `packageName`; `res/values/strings.xml` содержит `app_name`; тема существует.
- [ ] Используются только API, перечисленные в контракте; данные сохраняются реально (localStorage / IndexedDB / SQLite / SharedPreferences).
- [ ] Каждый файл приведён полностью, без «…» и заглушек.

## 9. HTTP API движка

Все запросы `/api/*` требуют `Authorization: Bearer <ENGINE_TOKEN>`, если токен задан на сервере.

| Метод и путь | Описание |
|---|---|
| `GET /health` | Состояние движка и инструментов |
| `GET /docs/agent-contract.md` | Этот документ |
| `POST /api/analyze` | multipart: `project` (ZIP) → JSON-анализ без сборки |
| `POST /api/keystore/validate` | multipart: `keystore`, `storePassword`, `keyAlias`, `keyPassword` |
| `POST /api/builds` | multipart: `project`, `options` (JSON), при Production — `keystore`, `storePassword`, `keyAlias`, `keyPassword` → `{"id": "..."}` |
| `GET /api/builds` | Список сборок |
| `GET /api/builds/{id}?logFrom=N` | Статус, этап, строки лога начиная с N |
| `GET /api/builds/{id}/apk` | Готовый подписанный APK |
| `DELETE /api/builds/{id}` | Удалить сборку |

`options`: `{"appName": "...", "packageName": "...", "versionName": "1.0.0", "versionCode": 1,
"orientation": "portrait", "permissions": ["internet"], "signing": "debug" | "keystore"}` — все поля необязательны.
''';
}
