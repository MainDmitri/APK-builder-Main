import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('priority: options > appbuilder.json > manifest > package.json > defaults', () {
    final a = analyzeFiles({
      'package.json': '{"name":"@scope/my-cool-app","version":"3.2.1","scripts":{"build":"vite build"}}',
      'public/manifest.json': '{"name":"From Manifest","orientation":"landscape-primary","theme_color":"#abc"}',
      'appbuilder.json': '{"packageName":"com.cfg.app","versionCode":7,"web":{"fullscreen":true}}',
    });
    final r = ResolvedAppConfig.resolve(a, const BuildOptions(versionName: '9.9.9'));
    expect(r.appName, 'From Manifest');
    expect(r.packageName, 'com.cfg.app');
    expect(r.versionName, '9.9.9');
    expect(r.versionCode, 7);
    expect(r.orientation, ScreenOrientation.landscape);
    expect(r.themeColor, '#AABBCC');
    expect(r.fullscreen, isTrue);
    expect(r.permissions, {AppPermission.internet});
    expect(r.validate(), isEmpty);
  });

  test('defaults derive package from name and use npm package name', () {
    final a = analyzeFiles({
      'package.json': '{"name":"my-cool-app","scripts":{"build":"vite build"}}',
    });
    final r = ResolvedAppConfig.resolve(a, const BuildOptions());
    expect(r.appName, 'My Cool App');
    expect(r.packageName, 'com.appbuilder.mycoolapp');
    expect(r.versionName, '1.0.0');
    expect(r.startUrl, 'index.html');
  });

  test('Android permission names: known ones map to ids, the rest go to the manifest as is', () {
    final a = analyzeFiles({
      'pubspec.yaml': 'name: scanner\ndependencies:\n  flutter:\n    sdk: flutter\n',
      'lib/main.dart': 'void main() {}',
      'appbuilder.json': '{"permissions":["INTERNET","ACCESS_NETWORK_STATE","android.permission.ACCESS_FINE_LOCATION",'
          '"POST_NOTIFICATIONS","WAKE_LOCK","ACCESS_WIFI_STATE","WAKE_LOCK","bluetooth-ish"]}',
    });
    expect(a.warnings.where((w) => w.contains('разрешение')), ['appbuilder.json: неизвестное разрешение «bluetooth-ish» пропущено.']);
    final r = ResolvedAppConfig.resolve(a, const BuildOptions());
    expect(r.permissions, {AppPermission.internet, AppPermission.location, AppPermission.notifications});
    expect(r.extraAndroidPermissions, ['android.permission.WAKE_LOCK', 'android.permission.ACCESS_WIFI_STATE']);
    expect(r.manifestPermissions.map((m) => m.name), containsAll(['android.permission.ACCESS_COARSE_LOCATION', 'android.permission.WAKE_LOCK']));
    expect(AppPermission.tryParse('camera'), AppPermission.camera);
    expect(AppPermission.tryParse('android.permission.CAMERA'), AppPermission.camera);
  });

  test('remote start url forces internet permission', () {
    final a = analyzeFiles({
      'index.html': '',
      'appbuilder.json': '{"permissions":["camera"],"web":{"startUrl":"https://example.com/"}}',
    });
    final r = ResolvedAppConfig.resolve(a, const BuildOptions());
    expect(r.isRemoteStart, isTrue);
    expect(r.permissions, containsAll([AppPermission.camera, AppPermission.internet]));
  });

  test('BuildOptions json roundtrip', () {
    const o = BuildOptions(
      appName: 'X',
      packageName: 'a.b',
      versionCode: 3,
      orientation: ScreenOrientation.portrait,
      permissions: {AppPermission.location},
      signing: SigningMode.keystore,
    );
    final back = BuildOptions.fromJson(o.toJson());
    expect(back.appName, 'X');
    expect(back.versionCode, 3);
    expect(back.orientation, ScreenOrientation.portrait);
    expect(back.permissions, {AppPermission.location});
    expect(back.signing, SigningMode.keystore);
  });
}
