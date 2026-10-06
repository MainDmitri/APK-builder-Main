# AppBuilder — ZIP → подписанный APK

Flutter-приложение (Android / Web / Windows / Linux / macOS) и сборщик **AppBuilder Engine**
(Docker), которые превращают ZIP с веб-кодом (HTML/JS, React/Vue/Vite через npm/yarn/pnpm)
или с Android-исходниками (Kotlin/Java) в подписанный APK. Встроены контракт для сторонних ИИ
и генератор «мега-промптов», чтобы ответ ChatGPT / Claude / DeepSeek собирался с первого раза.

## Где взять готовые файлы

| Что | Где |
|---|---|
| APK приложения AppBuilder | Releases → **app-latest** (`AppBuilder-*.apk`), там же Windows/Linux/Web |
| Docker-образ сборщика | `ghcr.io/maindmitri/appbuilder-engine:latest` |
| Контракт для ИИ | [`docs/agent-contract.md`](docs/agent-contract.md), `GET /docs/agent-contract.md` у движка, вкладка «Контракт» в приложении |

## Архитектура

```
packages/appbuilder_core/        общий Dart-пакет (Flutter-приложение + движок)
  lib/src/project_analyzer.dart  автоопределение содержимого ZIP и маршрутизация
  lib/src/analysis.dart          результат анализа, план сборки (BuildPlan/BuildStage)
  lib/src/resolver.dart          итоговые параметры: UI → appbuilder.json → manifest.json → package.json
  lib/src/agent_contract.dart    контракт для ИИ (источник docs/agent-contract.md)
  lib/src/prompt_generator.dart  генератор мега-промптов
  lib/src/toolchain.dart         версии AGP/Gradle/Kotlin/SDK/npm — единый источник правды
engine/                          AppBuilder Engine (Dart, AOT в Docker)
  bin/engine.dart                CLI: serve | build | analyze | contract | doctor | selftest
  lib/src/pipeline/              npm → WebView-оболочка / Gradle-обёртка → assembleRelease → zipalign → apksigner
  lib/src/server/                HTTP API (shelf), очередь сборок, multipart-загрузки
  templates/web_shell/           Android-проект WebView-оболочки (Java, WebViewAssetLoader)
  templates/native/              Gradle-обёртка для Kotlin/Java-исходников
  samples/                       5 реальных проектов для сквозной проверки (selftest в CI)
  Dockerfile                     Node 24 LTS + corepack, JDK 17, Gradle 9.3.1, SDK 36, build-tools 36.0.0
app/                             Flutter-клиент (Material 3, Provider)
  lib/services/backend/          EngineBackend (свой сервер) и GitHubBackend (GitHub Actions)
  lib/state/                     контроллеры: настройки, сборка, промпты
  lib/screens/                   Сборка, Промпты, Контракт, История, Настройки
.github/workflows/
  engine.yml                     тесты, Docker-образ, сборка всех samples внутри контейнера, публикация в GHCR
  app.yml                        APK + Web + Linux + Windows, релиз app-latest
  inbox-build.yml                «сервер без сервера»: сборка ZIP из inbox/ в GitHub Actions
```

### Конвейер сборки

```
ZIP ─► безопасная распаковка ─► анализ (приоритет: package.json → index.html → Android)
   ├─ Node.js:  удалить node_modules → npm ci|install / yarn / pnpm → run build → dist|build|out
   │            └─► как статический веб
   ├─ Веб:      assets/www + appbuilder-shell.json → WebView-оболочка (https://appassets.androidplatform.net/)
   ├─ Исходники: Gradle-проект из шаблона (namespace из пакета, Compose по импортам, иконки, лечение манифеста)
   └─ Gradle:   проект как есть (wrapper, если полный), lintVital отключён init-скриптом
─► gradle assembleRelease ─► zipalign -p 4 ─► apksigner (v1+v2+v3, debug или production keystore) ─► verify
```

## Запуск сборщика (свой сервер)

```bash
docker run -d --name appbuilder -p 8080:8080 \
  -e ENGINE_TOKEN=придумайте-токен \
  -v appbuilder-data:/data \
  ghcr.io/maindmitri/appbuilder-engine:latest
```

Образ приватный, пока пакет не сделан публичным (GitHub → Packages → appbuilder-engine → Package settings),
до этого нужен `docker login ghcr.io`. Или соберите сами:

```bash
ENGINE_TOKEN=придумайте-токен docker compose -f engine/docker-compose.yml up -d --build
```

Том `/data` хранит постоянный debug-ключ: без него после пересоздания контейнера APK нельзя будет
установить поверх старой версии. В приложении: «Настройки» → «Свой сервер» → `http://<IP компьютера>:8080` + токен.

CLI без сервера (внутри образа или при установленных SDK/Node/Gradle):

```bash
appbuilder-engine build project.zip -o app.apk
APPBUILDER_STORE_PASSWORD=... APPBUILDER_KEY_PASSWORD=... \
  appbuilder-engine build project.zip --keystore release.jks --key-alias upload -o app.apk
appbuilder-engine analyze project.zip
appbuilder-engine doctor
```

## Сборка без своего сервера (GitHub Actions)

1. Ветка с этим кодом должна быть веткой по умолчанию (или укажите её в настройках приложения).
2. Создайте fine-grained token: доступ к репозиторию, **Contents: Read and write**, **Actions: Read**.
3. В приложении: «Настройки» → «GitHub Actions» → владелец, репозиторий, токен.
4. Приложение коммитит `inbox/<id>/project.zip` + `request.json`, workflow **Inbox build** собирает APK
   и публикует пре-релиз `build-<id>`; приложение скачивает и устанавливает его.

Production-подпись в этом режиме — секреты репозитория `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.

## Разработка

```bash
cd packages/appbuilder_core && dart test
cd engine && dart test
cd app && flutter test && flutter run
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

Постоянный ключ подписи самого AppBuilder в CI: секреты `APP_KEYSTORE_BASE64`, `APP_KEYSTORE_PASSWORD`,
`APP_KEY_ALIAS`, `APP_KEY_PASSWORD` (без них используется ключ, сохранённый в кэше Actions).
