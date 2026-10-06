import 'dart:io';

import 'package:appbuilder_engine/engine.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

/// Engine config for tests: templates from the source tree, data in [dataDir].
EngineConfig testConfig(String dataDir, {String? token}) => EngineConfig(
      dataDir: dataDir,
      templatesDir: p.join(Directory.current.path, 'templates'),
      androidHome: Platform.environment['ANDROID_HOME'] ?? p.join(dataDir, 'no-sdk'),
      gradleCommand: 'gradle',
      port: 0,
      token: token,
    );

/// Zips a sample project into [targetDir] and returns the archive path.
Future<String> zipSample(String name, String targetDir) async {
  final zipPath = p.join(targetDir, '$name.zip');
  final encoder = ZipFileEncoder()..create(zipPath);
  await encoder.addDirectory(Directory(p.join('samples', name)), includeDirName: false);
  await encoder.close();
  return zipPath;
}
