import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';

/// Writes the agent contract to docs/agent-contract.md (repository root).
/// Usage: dart run tool/export_contract.dart [output-path]
void main(List<String> args) {
  final target = args.isNotEmpty ? args.first : '../../docs/agent-contract.md';
  final file = File(target)..createSync(recursive: true);
  file.writeAsStringSync(buildAgentContract());
  stdout.writeln('Contract v${Toolchain.contractVersion} written to ${file.absolute.path}');
}
