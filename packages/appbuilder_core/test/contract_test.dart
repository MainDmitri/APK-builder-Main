import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:test/test.dart';

void main() {
  test('docs/agent-contract.md is up to date (run: dart run tool/export_contract.dart)', () {
    final file = File('../../docs/agent-contract.md');
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), buildAgentContract());
  });

  test('contract quotes the toolchain', () {
    final c = buildAgentContract();
    expect(c, contains(Toolchain.androidGradlePlugin));
    expect(c, contains(Toolchain.webAssetOrigin));
    expect(c, contains('appbuilder.json'));
  });
}
