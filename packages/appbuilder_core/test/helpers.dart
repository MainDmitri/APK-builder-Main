import 'dart:convert';
import 'dart:typed_data';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:archive/archive.dart';

/// Builds a ZIP archive in memory from `path → text content`.
Uint8List zipOf(Map<String, String> files) {
  final archive = Archive();
  files.forEach((path, content) => archive.addFile(ArchiveFile.bytes(path, utf8.encode(content))));
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

ProjectAnalysis analyzeFiles(Map<String, String> files) =>
    const ProjectAnalyzer().analyze(ZipMemorySource.fromBytes(zipOf(files)));
