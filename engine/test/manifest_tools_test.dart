import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:appbuilder_engine/engine.dart';
import 'package:test/test.dart';

void main() {
  const manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.app">
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:label="@string/app_name" android:theme="@style/Theme.App">
        <activity android:name=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <activity android:name=".Other" />
        <activity android:name=".Settings" android:exported="false"></activity>
    </application>
</manifest>''';

  test('package attribute is removed', () {
    final out = ManifestTools.removePackageAttribute(manifest);
    expect(out, isNot(contains('package=')));
    expect(out, contains('xmlns:android'));
  });

  test('exported is added only to activities with intent filters', () {
    final out = ManifestTools.ensureExportedActivities(manifest);
    expect(out, contains('<activity android:name=".MainActivity" android:exported="true">'));
    expect(out, contains('<activity android:name=".Other" />'));
    expect(out, contains('android:name=".Settings" android:exported="false"'));
  });

  test('missing permissions are injected once', () {
    final out = ManifestTools.injectPermissions(manifest, [
      ...AppPermission.internet.manifestPermissions,
      ...AppPermission.camera.manifestPermissions,
    ]);
    expect('android.permission.INTERNET'.allMatches(out), hasLength(1));
    expect(out, contains('android.permission.CAMERA'));
    expect(out, contains('android.permission.ACCESS_NETWORK_STATE'));
  });

  test('launcher orientation', () {
    final out = ManifestTools.ensureLauncherOrientation(manifest, 'portrait');
    expect(out, contains('android:name=".MainActivity" android:screenOrientation="portrait">'));
    expect(ManifestTools.ensureLauncherOrientation(out, 'landscape'), out);
  });

  test('missing android namespace is added', () {
    expect(ManifestTools.ensureAndroidNamespace('<manifest><application/></manifest>'),
        startsWith('<manifest xmlns:android="http://schemas.android.com/apk/res/android">'));
  });

  test('referenced resources', () {
    expect(ManifestTools.referencedResources(manifest, 'style'), {'Theme.App'});
    expect(ManifestTools.referencedResources(manifest, 'string'), {'app_name'});
  });
}
