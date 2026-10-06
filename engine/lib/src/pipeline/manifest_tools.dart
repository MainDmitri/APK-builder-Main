import 'package:appbuilder_core/appbuilder_core.dart';

/// Small, conservative text transformations of AndroidManifest.xml used to
/// make AI-generated native sources compatible with AGP 8+/9.
abstract final class ManifestTools {
  /// AGP 8+ rejects the `package` attribute (namespace is set in Gradle).
  static String removePackageAttribute(String xml) =>
      xml.replaceFirstMapped(RegExp(r'(<manifest\b[^>]*?)\s+package\s*=\s*"[^"]*"', dotAll: true), (m) => m.group(1)!);

  static String ensureAndroidNamespace(String xml) {
    if (xml.contains('xmlns:android=')) return xml;
    return xml.replaceFirst(
        RegExp(r'<manifest\b'), '<manifest xmlns:android="http://schemas.android.com/apk/res/android"');
  }

  /// targetSdk 31+ requires android:exported on components with intent
  /// filters. Activities with an intent filter but no attribute get "true".
  static String ensureExportedActivities(String xml) {
    final starts = RegExp(r'<activity\b[^>]*>', dotAll: true).allMatches(xml).toList();
    var result = xml;
    for (final m in starts.reversed) {
      final tag = m.group(0)!;
      if (tag.endsWith('/>') || tag.contains('android:exported')) continue;
      final close = xml.indexOf('</activity>', m.end);
      if (close < 0) continue;
      if (!xml.substring(m.end, close).contains('<intent-filter')) continue;
      final patched = '${tag.substring(0, tag.length - 1)} android:exported="true">';
      result = result.replaceRange(m.start, m.end, patched);
    }
    return result;
  }

  /// Adds `android:screenOrientation` to the launcher activity when missing.
  static String ensureLauncherOrientation(String xml, String orientation) {
    final starts = RegExp(r'<activity\b[^>]*>', dotAll: true).allMatches(xml).toList();
    for (final m in starts) {
      final tag = m.group(0)!;
      if (tag.endsWith('/>')) continue;
      final close = xml.indexOf('</activity>', m.end);
      if (close < 0 || !xml.substring(m.end, close).contains('android.intent.category.LAUNCHER')) continue;
      if (tag.contains('android:screenOrientation')) return xml;
      return xml.replaceRange(m.start, m.end, '${tag.substring(0, tag.length - 1)} android:screenOrientation="$orientation">');
    }
    return xml;
  }

  /// Inserts `<uses-permission>` entries that are not declared yet.
  static String injectPermissions(String xml, Iterable<ManifestPermission> permissions) {
    final missing = permissions.where((perm) => !xml.contains('"${perm.name}"')).toList();
    if (missing.isEmpty) return xml;
    final open = RegExp(r'<manifest\b[^>]*>', dotAll: true).firstMatch(xml);
    if (open == null) return xml;
    final lines = missing.map((perm) => '\n    ${perm.toXml()}').join();
    return xml.replaceRange(open.end, open.end, lines);
  }

  static Set<String> referencedResources(String xml, String type) =>
      RegExp('@$type/([A-Za-z0-9_.]+)').allMatches(xml).map((m) => m.group(1)!).toSet();

  /// Manifest for loose sources (no AndroidManifest.xml in the archive).
  static String generate({
    required String mainActivity,
    required Iterable<ManifestPermission> permissions,
    required String orientation,
  }) {
    final perms = permissions.map((perm) => '    ${perm.toXml()}\n').join();
    return '''
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
$perms
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.App">
        <activity
            android:name="$mainActivity"
            android:exported="true"
            android:screenOrientation="$orientation"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
''';
  }
}
