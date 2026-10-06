import 'dart:convert';
import 'dart:io';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'process_runner.dart';

/// Safe ZIP extraction: rejects path traversal, absolute paths and archives
/// that unpack to more than [maxBytes] / [maxEntries]. Symlinks are skipped.
Future<List<String>> extractZipSafely(
  String zipPath,
  String destination, {
  required int maxBytes,
  required int maxEntries,
}) async {
  final skipped = <String>[];
  final input = InputFileStream(zipPath);
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (e) {
      throw BuildFailure('Файл не является корректным ZIP-архивом ($e).');
    }
    if (archive.length > maxEntries) {
      throw BuildFailure('В архиве ${archive.length} элементов — больше лимита $maxEntries.');
    }
    var total = 0;
    final root = p.normalize(p.absolute(destination));
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (name.isEmpty) continue;
      if (name.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(name) || name.split('/').contains('..')) {
        throw BuildFailure('Недопустимый путь в архиве: «$name».');
      }
      final target = p.normalize(p.join(root, name));
      if (!p.isWithin(root, target)) throw BuildFailure('Недопустимый путь в архиве: «$name».');
      if (entry.isSymbolicLink) {
        skipped.add(name);
        continue;
      }
      if (!entry.isFile) {
        Directory(target).createSync(recursive: true);
        continue;
      }
      total += entry.size;
      if (total > maxBytes) {
        throw BuildFailure('Распакованный архив больше ${maxBytes ~/ (1024 * 1024)} МБ.');
      }
      File(target).parent.createSync(recursive: true);
      final out = OutputFileStream(target);
      entry.writeContent(out);
      await out.close();
    }
  } finally {
    await input.close();
  }
  return skipped;
}

/// [ProjectFileSource] over an extracted directory.
class DirectorySource implements ProjectFileSource {
  DirectorySource(this.root) {
    final dir = Directory(root);
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      final rel = p.relative(e.path, from: root).replaceAll('\\', '/');
      if (e is Link) {
        symlinks.add(rel);
      } else if (e is File) {
        _paths.add(rel);
      }
    }
  }

  static const int maxTextBytes = 2 * 1024 * 1024;

  final String root;
  final List<String> _paths = [];

  @override
  final List<String> symlinks = [];

  @override
  List<String> get paths => _paths;

  @override
  String? readText(String path) {
    final f = File(p.join(root, path));
    if (!f.existsSync() || f.lengthSync() > maxTextBytes) return null;
    return utf8.decode(f.readAsBytesSync(), allowMalformed: true);
  }
}

/// Recursively copies [from] into [to]. Entries for which [exclude] returns
/// true (relative `/`-separated path) are skipped. Symlinks are never copied.
void copyDirectory(String from, String to, {bool Function(String relative)? exclude}) {
  final src = Directory(from);
  Directory(to).createSync(recursive: true);
  for (final e in src.listSync(recursive: true, followLinks: false)) {
    final rel = p.relative(e.path, from: from).replaceAll('\\', '/');
    if (exclude != null && exclude(rel)) continue;
    final target = p.join(to, rel);
    if (e is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (e is File) {
      File(target).parent.createSync(recursive: true);
      e.copySync(target);
    }
  }
}

/// Deletes a path if it exists, ignoring errors (cleanup).
void deleteQuietly(String path) {
  try {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      Directory(path).deleteSync(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      File(path).deleteSync();
    }
  } on FileSystemException {
    // Best effort.
  }
}
