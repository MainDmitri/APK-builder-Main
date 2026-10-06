import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Read-only view of project files (paths are relative, `/`-separated).
abstract interface class ProjectFileSource {
  /// All regular files.
  List<String> get paths;

  /// Symbolic links (forbidden by the contract, never extracted).
  List<String> get symlinks;

  /// Text content of a small text file, or `null` when missing / too large.
  String? readText(String path);
}

/// Project files taken from an in-memory ZIP archive (works on every
/// platform, including Flutter Web).
class ZipMemorySource implements ProjectFileSource {
  ZipMemorySource._(this._files, this.symlinks);

  /// Decodes [bytes]. Throws [FormatException] if this is not a ZIP archive.
  factory ZipMemorySource.fromBytes(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const FormatException('Файл не является ZIP-архивом (нет сигнатуры PK).');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Файл не является корректным ZIP-архивом: $e');
    }
    final files = <String, ArchiveFile>{};
    final links = <String>[];
    for (final f in archive) {
      final name = f.name.replaceAll('\\', '/');
      if (f.isSymbolicLink) {
        links.add(name);
        continue;
      }
      if (!f.isFile) continue;
      files[name] = f;
    }
    return ZipMemorySource._(files, links);
  }

  static const int maxTextBytes = 2 * 1024 * 1024;

  final Map<String, ArchiveFile> _files;

  @override
  final List<String> symlinks;

  @override
  List<String> get paths => _files.keys.toList(growable: false);

  @override
  String? readText(String path) {
    final f = _files[path];
    if (f == null || f.size > maxTextBytes) return null;
    final bytes = f.readBytes();
    if (bytes == null) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }
}
