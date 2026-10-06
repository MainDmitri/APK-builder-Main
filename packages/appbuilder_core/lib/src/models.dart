import 'dart:convert';

/// Kind of project detected inside an uploaded ZIP archive.
enum ProjectKind {
  nodeProject('node', 'Node.js-проект (npm / yarn / pnpm)'),
  staticWeb('static-web', 'Статический веб (HTML / CSS / JS)'),
  nativeGradle('native-gradle', 'Нативный Android: Gradle-проект'),
  nativeSources('native-sources', 'Нативный Android: исходники Java/Kotlin'),
  unsupported('unsupported', 'Не распознано');

  const ProjectKind(this.id, this.title);

  final String id;
  final String title;

  bool get isWeb => this == nodeProject || this == staticWeb;
  bool get isNative => this == nativeGradle || this == nativeSources;
}

enum ScreenOrientation {
  portrait('portrait', 'Портретная', 'portrait'),
  landscape('landscape', 'Альбомная', 'sensorLandscape'),
  sensor('sensor', 'По датчику (авто)', 'fullSensor');

  const ScreenOrientation(this.id, this.title, this.androidValue);

  final String id;
  final String title;

  /// Value for `android:screenOrientation`.
  final String androidValue;

  static ScreenOrientation? tryParse(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    for (final o in values) {
      if (o.id == v) return o;
    }
    // Web App Manifest orientation values.
    if (v.startsWith('portrait')) return ScreenOrientation.portrait;
    if (v.startsWith('landscape')) return ScreenOrientation.landscape;
    if (v == 'any' || v == 'natural' || v == 'unspecified' || v == 'fullsensor') {
      return ScreenOrientation.sensor;
    }
    return null;
  }
}

/// A `<uses-permission>` entry.
class ManifestPermission {
  const ManifestPermission(this.name, {this.maxSdkVersion});

  final String name;
  final int? maxSdkVersion;

  String toXml() => maxSdkVersion == null
      ? '<uses-permission android:name="$name" />'
      : '<uses-permission android:name="$name" android:maxSdkVersion="$maxSdkVersion" />';
}

enum AppPermission {
  internet('internet', 'Интернет', [
    ManifestPermission('android.permission.INTERNET'),
    ManifestPermission('android.permission.ACCESS_NETWORK_STATE'),
  ]),
  storage('storage', 'Хранилище (файлы)', [
    ManifestPermission('android.permission.WRITE_EXTERNAL_STORAGE', maxSdkVersion: 28),
    ManifestPermission('android.permission.READ_EXTERNAL_STORAGE', maxSdkVersion: 32),
  ]),
  location('location', 'Геолокация', [
    ManifestPermission('android.permission.ACCESS_FINE_LOCATION'),
    ManifestPermission('android.permission.ACCESS_COARSE_LOCATION'),
  ]),
  camera('camera', 'Камера', [ManifestPermission('android.permission.CAMERA')]),
  microphone('microphone', 'Микрофон', [
    ManifestPermission('android.permission.RECORD_AUDIO'),
    ManifestPermission('android.permission.MODIFY_AUDIO_SETTINGS'),
  ]),
  vibration('vibration', 'Вибрация', [ManifestPermission('android.permission.VIBRATE')]),
  notifications('notifications', 'Уведомления (только нативные)', [
    ManifestPermission('android.permission.POST_NOTIFICATIONS'),
  ]);

  const AppPermission(this.id, this.title, this.manifestPermissions);

  final String id;
  final String title;
  final List<ManifestPermission> manifestPermissions;

  /// Permissions the WebView shell knows how to use.
  static const Set<AppPermission> webSupported = {
    internet,
    storage,
    location,
    camera,
    microphone,
    vibration,
  };

  static AppPermission? tryParse(String value) {
    final v = value.trim().toLowerCase();
    for (final p in values) {
      if (p.id == v) return p;
    }
    return null;
  }
}

enum SigningMode {
  /// Engine's persistent debug keystore (androiddebugkey / android).
  debug('debug', 'Debug Key'),

  /// Keystore uploaded together with the build request.
  keystore('keystore', 'Production Keystore'),

  /// GitHub mode: keystore stored in repository secrets.
  repoSecrets('repo-secrets', 'Keystore из секретов GitHub');

  const SigningMode(this.id, this.title);

  final String id;
  final String title;

  static SigningMode parse(String? value) {
    for (final m in values) {
      if (m.id == value) return m;
    }
    return SigningMode.debug;
  }
}

/// Build parameters chosen by the user. Every field is an optional override:
/// `null` means "take it from appbuilder.json / manifest.json / defaults".
class BuildOptions {
  const BuildOptions({
    this.appName,
    this.packageName,
    this.versionName,
    this.versionCode,
    this.orientation,
    this.permissions,
    this.signing = SigningMode.debug,
  });

  final String? appName;
  final String? packageName;
  final String? versionName;
  final int? versionCode;
  final ScreenOrientation? orientation;
  final Set<AppPermission>? permissions;
  final SigningMode signing;

  Map<String, Object?> toJson() => {
        if (appName != null) 'appName': appName,
        if (packageName != null) 'packageName': packageName,
        if (versionName != null) 'versionName': versionName,
        if (versionCode != null) 'versionCode': versionCode,
        if (orientation != null) 'orientation': orientation!.id,
        if (permissions != null) 'permissions': permissions!.map((p) => p.id).toList(),
        'signing': signing.id,
      };

  factory BuildOptions.fromJson(Map<String, Object?> json) {
    final perms = json['permissions'];
    return BuildOptions(
      appName: _nonEmpty(json['appName']),
      packageName: _nonEmpty(json['packageName']),
      versionName: _nonEmpty(json['versionName']),
      versionCode: switch (json['versionCode']) {
        final int v => v,
        final String s => int.tryParse(s),
        _ => null,
      },
      orientation: ScreenOrientation.tryParse(json['orientation'] as String?),
      permissions: perms is List
          ? perms.whereType<String>().map(AppPermission.tryParse).whereType<AppPermission>().toSet()
          : null,
      signing: SigningMode.parse(json['signing'] as String?),
    );
  }
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final t = value.trim();
  return t.isEmpty ? null : t;
}

/// Parsed `appbuilder.json` — optional project-level build configuration.
class AppBuilderConfig {
  const AppBuilderConfig({
    this.appName,
    this.packageName,
    this.versionName,
    this.versionCode,
    this.orientation,
    this.permissions,
    this.outputDir,
    this.startUrl,
    this.fullscreen,
    this.themeColor,
    this.backgroundColor,
    this.openLinksExternally,
    this.dependencies = const [],
    this.compose,
  });

  final String? appName;
  final String? packageName;
  final String? versionName;
  final int? versionCode;
  final ScreenOrientation? orientation;
  final Set<AppPermission>? permissions;

  // web.*
  final String? outputDir;
  final String? startUrl;
  final bool? fullscreen;
  final String? themeColor;
  final String? backgroundColor;
  final bool? openLinksExternally;

  // android.*
  final List<String> dependencies;
  final bool? compose;

  /// Parses appbuilder.json. Problems are appended to [errors] / [warnings].
  static AppBuilderConfig parse(String source, List<String> errors, List<String> warnings) {
    final Object? decoded;
    try {
      decoded = jsonDecodeLenient(source);
    } on FormatException catch (e) {
      errors.add('appbuilder.json: некорректный JSON (${e.message}).');
      return const AppBuilderConfig();
    }
    if (decoded is! Map) {
      errors.add('appbuilder.json: корень должен быть JSON-объектом.');
      return const AppBuilderConfig();
    }
    final web = decoded['web'] is Map ? decoded['web'] as Map : const {};
    final android = decoded['android'] is Map ? decoded['android'] as Map : const {};

    Set<AppPermission>? permissions;
    final rawPerms = decoded['permissions'];
    if (rawPerms is List) {
      permissions = {};
      for (final p in rawPerms) {
        final parsed = p is String ? AppPermission.tryParse(p) : null;
        if (parsed == null) {
          warnings.add('appbuilder.json: неизвестное разрешение «$p» пропущено.');
        } else {
          permissions.add(parsed);
        }
      }
    }

    final deps = <String>[];
    final rawDeps = android['dependencies'];
    if (rawDeps is List) {
      for (final d in rawDeps) {
        if (d is String && dependencyPattern.hasMatch(d.trim())) {
          deps.add(d.trim());
        } else {
          errors.add('appbuilder.json: зависимость «$d» должна иметь вид group:artifact:version.');
        }
      }
    }

    final orientationRaw = decoded['orientation'];
    final orientation = ScreenOrientation.tryParse(orientationRaw as String?);
    if (orientationRaw != null && orientation == null) {
      warnings.add('appbuilder.json: orientation «$orientationRaw» не поддерживается (portrait | landscape | sensor).');
    }

    return AppBuilderConfig(
      appName: _nonEmpty(decoded['appName']),
      packageName: _nonEmpty(decoded['packageName']),
      versionName: _nonEmpty(decoded['versionName']),
      versionCode: decoded['versionCode'] is int ? decoded['versionCode'] as int : null,
      orientation: orientation,
      permissions: permissions,
      outputDir: _nonEmpty(web['outputDir']),
      startUrl: _nonEmpty(web['startUrl']),
      fullscreen: web['fullscreen'] is bool ? web['fullscreen'] as bool : null,
      themeColor: _nonEmpty(web['themeColor']),
      backgroundColor: _nonEmpty(web['backgroundColor']),
      openLinksExternally: web['openLinksExternally'] is bool ? web['openLinksExternally'] as bool : null,
      dependencies: deps,
      compose: android['compose'] is bool ? android['compose'] as bool : null,
    );
  }
}

/// Maven coordinate `group:artifact:version`.
final RegExp dependencyPattern = RegExp(r'^[A-Za-z0-9_.\-]+:[A-Za-z0-9_.\-]+:[A-Za-z0-9_.\-+]+$');

/// Icon entry of a Web App Manifest.
class WebManifestIcon {
  const WebManifestIcon({required this.src, this.sizes, this.type, this.purpose});

  final String src;
  final String? sizes;
  final String? type;
  final String? purpose;

  /// Largest declared edge in pixels (`any` → 4096, unknown → 0).
  int get maxEdge {
    final s = sizes;
    if (s == null) return 0;
    if (s.contains('any')) return 4096;
    var best = 0;
    for (final part in s.split(RegExp(r'\s+'))) {
      final m = RegExp(r'^(\d+)x(\d+)$', caseSensitive: false).firstMatch(part);
      if (m != null) {
        final edge = int.parse(m.group(1)!);
        if (edge > best) best = edge;
      }
    }
    return best;
  }

  Map<String, Object?> toJson() => {
        'src': src,
        if (sizes != null) 'sizes': sizes,
        if (type != null) 'type': type,
        if (purpose != null) 'purpose': purpose,
      };
}

/// Parsed Web App Manifest (`manifest.json` / `manifest.webmanifest`).
class WebManifest {
  const WebManifest({
    this.name,
    this.shortName,
    this.startUrl,
    this.display,
    this.orientation,
    this.themeColor,
    this.backgroundColor,
    this.icons = const [],
  });

  final String? name;
  final String? shortName;
  final String? startUrl;
  final String? display;
  final String? orientation;
  final String? themeColor;
  final String? backgroundColor;
  final List<WebManifestIcon> icons;

  static WebManifest? parse(String source, List<String> warnings, String path) {
    final Object? decoded;
    try {
      decoded = jsonDecodeLenient(source);
    } on FormatException catch (e) {
      warnings.add('$path: некорректный JSON (${e.message}) — манифест проигнорирован.');
      return null;
    }
    if (decoded is! Map) {
      warnings.add('$path: корень должен быть объектом — манифест проигнорирован.');
      return null;
    }
    final icons = <WebManifestIcon>[];
    if (decoded['icons'] is List) {
      for (final i in decoded['icons'] as List) {
        if (i is Map && i['src'] is String) {
          icons.add(WebManifestIcon(
            src: i['src'] as String,
            sizes: i['sizes'] as String?,
            type: i['type'] as String?,
            purpose: i['purpose'] as String?,
          ));
        }
      }
    }
    return WebManifest(
      name: _nonEmpty(decoded['name']),
      shortName: _nonEmpty(decoded['short_name']),
      startUrl: _nonEmpty(decoded['start_url']),
      display: _nonEmpty(decoded['display']),
      orientation: _nonEmpty(decoded['orientation']),
      themeColor: _nonEmpty(decoded['theme_color']),
      backgroundColor: _nonEmpty(decoded['background_color']),
      icons: icons,
    );
  }

  Map<String, Object?> toJson() => {
        if (name != null) 'name': name,
        if (shortName != null) 'short_name': shortName,
        if (startUrl != null) 'start_url': startUrl,
        if (display != null) 'display': display,
        if (orientation != null) 'orientation': orientation,
        if (themeColor != null) 'theme_color': themeColor,
        if (backgroundColor != null) 'background_color': backgroundColor,
        'icons': icons.map((i) => i.toJson()).toList(),
      };
}

/// JSON decoding that tolerates a UTF-8 BOM, which some editors (and AIs)
/// put at the start of files.
Object? jsonDecodeLenient(String source) {
  var s = source;
  if (s.startsWith('\uFEFF')) s = s.substring(1);
  return jsonDecode(s);
}
