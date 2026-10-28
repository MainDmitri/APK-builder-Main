import 'package:appbuilder_engine/src/pipeline/plist.dart';
import 'package:test/test.dart';

const _plist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Old</string>
	<!-- scene manifest with nested dictionaries -->
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UISceneConfigurations</key>
		<dict>
			<key>UIWindowSceneSessionRoleApplication</key>
			<array>
				<dict>
					<key>UISceneConfigurationName</key>
					<string>Default Configuration</string>
				</dict>
			</array>
		</dict>
	</dict>
	<key>UIBackgroundModes</key>
	<array/>
	<key>LSRequiresIPhoneOS</key>
	<true/>
</dict>
</plist>
''';

void main() {
  test('replaces top-level values of any type and keeps nested dictionaries', () {
    var out = PlistEditor.set(_plist, 'CFBundleDisplayName', 'A & B');
    out = PlistEditor.set(out, 'UIBackgroundModes', ['audio']);
    out = PlistEditor.set(out, 'LSRequiresIPhoneOS', false);
    out = PlistEditor.set(out, 'NSAppTransportSecurity', {'NSAllowsLocalNetworking': true});
    out = PlistEditor.set(out, 'NSBonjourServices', ['_http._tcp', '_rtsp._tcp']);
    out = PlistEditor.set(out, 'MaxItems', 3);

    expect(out, contains('<key>CFBundleDisplayName</key>\n\t<string>A &amp; B</string>'));
    expect(out, contains('<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>'));
    expect(out, contains('<key>LSRequiresIPhoneOS</key>\n\t<false/>'));
    expect(out, contains('<key>NSAllowsLocalNetworking</key>\n\t\t<true/>'));
    expect(out, contains('<key>MaxItems</key>\n\t<integer>3</integer>'));
    expect(out, contains('<string>Default Configuration</string>'));
    expect(out.trimRight(), endsWith('</dict>\n</plist>'));
    expect(PlistEditor.hasKey(out, 'NSBonjourServices'), isTrue);
    // Keys inside nested dictionaries are not top-level keys.
    expect(PlistEditor.hasKey(out, 'UISceneConfigurations'), isFalse);
    expect(PlistEditor.set(out, 'NSBonjourServices', ['_x._tcp']), isNot(contains('_rtsp._tcp')));
  });

  test('broken property lists are reported', () {
    expect(() => PlistEditor.set('<plist><array/></plist>', 'A', 'b'), throwsFormatException);
    expect(() => PlistEditor.set('<plist version="1.0">\n<dict>\n<key>A</key>\n<dict>\n</plist>', 'A', 'b'),
        throwsFormatException);
  });
}
