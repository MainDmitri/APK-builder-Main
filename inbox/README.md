# inbox/ — сборка APK через GitHub Actions (без своего сервера)

Каждая папка `inbox/<id>/` — один запрос на сборку:

```
inbox/<id>/project.zip     ← проект по контракту docs/agent-contract.md
inbox/<id>/request.json    ← параметры сборки
```

`request.json`:

```json
{
  "id": "<id>",
  "options": {
    "appName": "Мои заметки",
    "packageName": "com.example.notes",
    "versionName": "1.0.0",
    "versionCode": 1,
    "orientation": "portrait",
    "permissions": ["internet"],
    "signing": "debug"
  }
}
```

После коммита workflow **Inbox build** собирает APK тем же движком (`engine/`) и публикует
пре-релиз `build-<id>` с файлами `*.apk`, `build.log`, `result.json`.

Подпись:
- `"signing": "debug"` — debug-ключ, создаётся на время сборки;
- `"signing": "repo-secrets"` — production-ключ из секретов репозитория
  (Settings → Secrets and variables → Actions): `KEYSTORE_BASE64` (`base64 -w0 release.jks`),
  `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.

Flutter-приложение AppBuilder (режим «GitHub Actions») делает всё это автоматически.
