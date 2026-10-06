import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedFile {
  const PickedFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

/// File picking and saving on every platform (Android SAF, desktop dialogs,
/// browser download on the web).
class FileService {
  const FileService();

  Future<PickedFile?> pickZip() => _pick(type: FileType.custom, extensions: const ['zip']);

  /// Keystores have no standard MIME type, so any file is accepted and the
  /// format is checked by magic bytes afterwards.
  Future<PickedFile?> pickKeystore() => _pick(type: FileType.any);

  Future<PickedFile?> _pick({required FileType type, List<String>? extensions}) async {
    final file = await FilePicker.pickFile(type: type, allowedExtensions: extensions);
    if (file == null) return null;
    return PickedFile(file.name, await file.readAsBytes());
  }

  /// Returns a human readable location, or null when the user cancelled.
  Future<String?> save(String fileName, Uint8List bytes, {String mimeType = 'application/octet-stream'}) async {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
    if (uri == null) return null;
    return uri.scheme == 'file' ? uri.toFilePath() : fileName;
  }
}
