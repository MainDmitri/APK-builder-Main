# AppBuilder — ZIP → подписанный APK

Приложение (Android / Windows / Linux / Web) и сборщик **AppBuilder Engine**, которые превращают ZIP
с веб-кодом (HTML/JS, React/Vue/Vite через npm/yarn/pnpm) или с Android-исходниками (Kotlin/Java)
в подписанный APK. Встроены контракт для ИИ и генератор «мега-промптов», чтобы код от
ChatGPT / Claude / DeepSeek собирался с первого раза.

## Быстрый старт (без своего сервера, бесплатно)

1. **Установите приложение.** Releases → **app-latest** → `AppBuilder-*.apk`
   (разрешите установку из неизвестных источников).
2. **Создайте свой сборщик.** Нажмите зелёную кнопку **Use this template** → **Create a new repository**.
   Сборка ваших APK пойдёт в вашем репозитории, на ваших минутах GitHub Actions.
   Если делаете репозиторий приватным — ваши проекты и APK никто не увидит;
   в публичном Actions бесплатны без лимита минут.
3. **Создайте токен:** https://github.com/settings/personal-access-tokens/new
   - Repository access → Only select repositories → ваш новый репозиторий;
   - Permissions → **Contents: Read and write**, **Actions: Read-only**;
   - скопируйте токен `github_pat_…` (показывается один раз).
4. **Настройте приложение:** «Настройки» → «GitHub Actions» → ваш логин, имя репозитория, токен
   (ветку можно не указывать) → «Сохранить и проверить подключение».
5. **Соберите:** «Сборка» → «Выбрать ZIP» → «Собрать APK». Через 2–5 минут APK можно установить
   или сохранить; все сборки — во вкладке «История» и в Releases вашего репозитория (`build-…`).

Генератор промптов и контракт для ИИ работают сразу, без настройки.

### Своя подпись (Google Play, обновления)

В вашем репозитории: Settings → Secrets and variables → Actions → добавьте
`KEYSTORE_BASE64` (`base64 -w0 release.jks`), `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`
и выберите в приложении подпись «Keystore из секретов GitHub».

## Свой сервер сборки (Docker)

Образ публикуется workflow **Engine** в `ghcr.io/<владелец>/<репозиторий>:latest`.

```bash
docker run -d --name appbuilder -p 8080:8080 \
  -e ENGINE_TOKEN=придумайте-токен \
  -v appbuilder-data:/data \
  ghcr.io/<владелец>/<репозиторий>:latest
# или из исходников:
ENGINE_TOKEN=придумайте-токен docker compose -f engine/docker-compose.yml up -d --build
```

В приложении: «Настройки» → «Свой сервер» → `http://<IP компьютера>:8080` + токен.
Том `/data` хранит постоянный debug-ключ (иначе APK нельзя ставить поверх старой версии).
Сервер выполняет код загружаемых проектов — давайте доступ только тем, кому доверяете.

## Что умеет

- автоопределение проекта: `package.json` → `index.html` → Android; вложенные папки `client/`, `frontend/`, `web/`, `android/`;
- двухэтапная сборка Node.js (npm / yarn / pnpm → `dist`/`build`/`out` → WebView-оболочка);
- WebView-оболочка: `https://appassets.androidplatform.net/`, localStorage/IndexedDB, файлы, камера, микрофон,
  геолокация, вибрация, скачивания, полноэкранный режим, кнопка «Назад»;
- Kotlin/Java-исходники без Gradle-файлов (Compose или View), полный Gradle-проект;
- zipalign + apksigner (v1 + v2 + v3), debug-ключ или свой keystore с проверкой паролей;
- контракт для ИИ: [`docs/agent-contract.md`](docs/agent-contract.md), `GET /docs/agent-contract.md`.

## Устройство репозитория

```
packages/appbuilder_core/   анализатор ZIP, план сборки, контракт, генератор промптов, версии toolchain
engine/                     сборщик (Dart): CLI + HTTP API, шаблоны Android-проектов, Dockerfile, примеры
app/                        Flutter-приложение (Material 3, Provider)
.github/workflows/
  app.yml                   APK + Web + Linux + Windows, проверка на эмуляторах, релиз app-latest
  engine.yml                тесты, Docker-образ, сборка и запуск всех примеров на эмуляторах
  inbox-build.yml           сборка ZIP из inbox/ (режим «GitHub Actions» в приложении)
```

## Разработка

```bash
cd packages/appbuilder_core && dart test
cd engine && dart test
cd app && flutter test && flutter run
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

Постоянный ключ подписи самого AppBuilder в CI: секреты `APP_KEYSTORE_BASE64`, `APP_KEYSTORE_PASSWORD`,
`APP_KEY_ALIAS`, `APP_KEY_PASSWORD` (без них используется ключ из кэша Actions).
