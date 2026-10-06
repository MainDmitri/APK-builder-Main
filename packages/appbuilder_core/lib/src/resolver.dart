import 'analysis.dart';
import 'models.dart';
import 'validators.dart';

/// Effective application parameters after merging, in priority order:
/// user options (UI / API) → appbuilder.json → web manifest / package.json /
/// native sources → defaults.
class ResolvedAppConfig {
  const ResolvedAppConfig({
    required this.appName,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.orientation,
    required this.permissions,
    required this.fullscreen,
    required this.themeColor,
    required this.backgroundColor,
    required this.startUrl,
    required this.openLinksExternally,
  });

  final String appName;
  final String packageName;
  final String versionName;
  final int versionCode;
  final ScreenOrientation orientation;
  final Set<AppPermission> permissions;
  final bool fullscreen;
  final String themeColor;
  final String backgroundColor;

  /// Relative path inside the web root (e.g. `index.html`) or an absolute
  /// `https://` URL for remote-site wrappers.
  final String startUrl;
  final bool openLinksExternally;

  bool get isRemoteStart => startUrl.startsWith('https://') || startUrl.startsWith('http://');

  /// Validation errors of the final values.
  List<String> validate() => [
        if (Validators.appName(appName) case final e?) 'Название: $e',
        if (Validators.packageName(packageName) case final e?) 'Пакет: $e',
        if (Validators.versionName(versionName) case final e?) 'versionName: $e',
        if (Validators.versionCode('$versionCode') case final e?) 'versionCode: $e',
        if (Validators.hexColor(themeColor) case final e?) 'theme_color: $e',
        if (Validators.hexColor(backgroundColor) case final e?) 'background_color: $e',
      ];

  Map<String, Object?> toJson() => {
        'appName': appName,
        'packageName': packageName,
        'versionName': versionName,
        'versionCode': versionCode,
        'orientation': orientation.id,
        'permissions': permissions.map((p) => p.id).toList(),
        'fullscreen': fullscreen,
        'themeColor': themeColor,
        'backgroundColor': backgroundColor,
        'startUrl': startUrl,
        'openLinksExternally': openLinksExternally,
      };

  static ResolvedAppConfig resolve(ProjectAnalysis analysis, BuildOptions options) {
    final config = analysis.config ?? const AppBuilderConfig();
    final manifest = analysis.manifest;
    final native = analysis.native;

    final appName = options.appName ??
        config.appName ??
        manifest?.name ??
        manifest?.shortName ??
        _prettify(analysis.node?.packageName) ??
        'My App';

    final packageName = options.packageName ??
        config.packageName ??
        native?.applicationId ??
        'com.appbuilder.${Validators.packageSegmentFrom(appName)}';

    final versionName = options.versionName ?? config.versionName ?? analysis.node?.packageVersion ?? '1.0.0';
    final versionCode = options.versionCode ?? config.versionCode ?? 1;

    final orientation = options.orientation ??
        config.orientation ??
        ScreenOrientation.tryParse(manifest?.orientation) ??
        ScreenOrientation.sensor;

    final permissions = options.permissions ?? config.permissions ?? {AppPermission.internet};

    final display = manifest?.display;
    final fullscreen = config.fullscreen ?? display == 'fullscreen';

    final themeColor = _normalizeColor(config.themeColor ?? manifest?.themeColor) ?? '#1565C0';
    final backgroundColor = _normalizeColor(config.backgroundColor ?? manifest?.backgroundColor) ?? '#FFFFFF';

    var startUrl = config.startUrl ?? manifest?.startUrl ?? 'index.html';
    if (!startUrl.startsWith('https://') && !startUrl.startsWith('http://')) {
      startUrl = startUrl.replaceFirst(RegExp(r'^(\./|/)+'), '');
      startUrl = startUrl.split('#').first;
      if (startUrl.isEmpty || startUrl == '.') startUrl = 'index.html';
    }

    return ResolvedAppConfig(
      appName: appName,
      packageName: packageName,
      versionName: versionName,
      versionCode: versionCode,
      orientation: orientation,
      permissions: {
        ...permissions,
        // A remote start page is useless without network access.
        if (startUrl.startsWith('http')) AppPermission.internet,
      },
      fullscreen: fullscreen,
      themeColor: themeColor,
      backgroundColor: backgroundColor,
      startUrl: startUrl,
      openLinksExternally: config.openLinksExternally ?? true,
    );
  }

  static String? _prettify(String? npmName) {
    if (npmName == null || npmName.isEmpty) return null;
    final base = npmName.contains('/') ? npmName.split('/').last : npmName;
    final words = base.split(RegExp(r'[-_.\s]+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return null;
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }

  /// Accepts `#RGB`, `#RRGGBB`, `#RRGGBBAA`; returns `#RRGGBB` or null.
  static String? _normalizeColor(String? value) {
    if (value == null) return null;
    final v = value.trim();
    final short = RegExp(r'^#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])$').firstMatch(v);
    if (short != null) {
      return '#${short.group(1)! * 2}${short.group(2)! * 2}${short.group(3)! * 2}'.toUpperCase();
    }
    final long = RegExp(r'^#([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?$').firstMatch(v);
    return long == null ? null : '#${long.group(1)!.toUpperCase()}';
  }
}
