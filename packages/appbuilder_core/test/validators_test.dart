import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:test/test.dart';

void main() {
  test('package names', () {
    expect(Validators.packageName('com.example.app'), isNull);
    expect(Validators.packageName('com.example'), isNull);
    expect(Validators.packageName('example'), isNotNull);
    expect(Validators.packageName('com.1example.app'), isNotNull);
    expect(Validators.packageName('com.example.new'), isNotNull);
    expect(Validators.packageName('com.my-app.x'), isNotNull);
  });

  test('keystore magic bytes', () {
    expect(Validators.keystoreBytes([0xFE, 0xED, 0xFE, 0xED]), isNull);
    expect(Validators.keystoreBytes([0x30, 0x82, 0x0A, 0x01]), isNull);
    expect(Validators.keystoreBytes([0x50, 0x4B, 0x03, 0x04]), isNotNull);
  });

  test('package segment from arbitrary text', () {
    expect(Validators.packageSegmentFrom('Мои заметки'), 'app');
    expect(Validators.packageSegmentFrom('2048 Game!'), 'game');
    expect(Validators.packageSegmentFrom('new'), 'newapp');
  });

  test('versions and colors', () {
    expect(Validators.versionCode('0'), isNotNull);
    expect(Validators.versionCode('12'), isNull);
    expect(Validators.versionName('1.0.0-beta+2'), isNull);
    expect(Validators.hexColor('#12AB9f'), isNull);
    expect(Validators.hexColor('red'), isNotNull);
  });
}
