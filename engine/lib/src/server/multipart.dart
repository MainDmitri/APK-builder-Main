import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

/// HTTP error with a status code and user-facing message.
class HttpError implements Exception {
  HttpError(this.status, this.message);

  final int status;
  final String message;
}

class UploadedFile {
  UploadedFile(this.file, this.filename, this.size);

  final File file;
  final String filename;
  final int size;
}

class MultipartForm {
  final Map<String, String> fields = {};
  final Map<String, UploadedFile> files = {};

  /// Removes uploaded files that were not taken over by the caller.
  void cleanup() {
    for (final f in files.values) {
      if (f.file.existsSync()) f.file.deleteSync();
    }
  }
}

final _random = Random.secure();

/// Streams a multipart/form-data body to disk (files) and memory (fields).
Future<MultipartForm> readMultipart(Request request, {required String tempDir, required int maxBytes}) async {
  final contentType = request.headers['content-type'];
  if (contentType == null || !contentType.toLowerCase().startsWith('multipart/form-data')) {
    throw HttpError(415, 'Ожидается multipart/form-data.');
  }
  final boundary = MediaType.parse(contentType).parameters['boundary'];
  if (boundary == null) throw HttpError(400, 'В Content-Type нет boundary.');

  Directory(tempDir).createSync(recursive: true);
  final form = MultipartForm();
  var total = 0;
  try {
    await for (final part in MimeMultipartTransformer(boundary).bind(request.read())) {
      final disposition = part.headers['content-disposition'] ?? '';
      final name = RegExp(r'\bname="([^"]*)"').firstMatch(disposition)?.group(1);
      final filename = RegExp(r'\bfilename="([^"]*)"').firstMatch(disposition)?.group(1);
      if (name == null) {
        await part.drain<void>();
        continue;
      }
      if (filename != null) {
        final rnd = List.generate(6, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        final file = File(p.join(tempDir, 'upload-$rnd'));
        final sink = file.openWrite();
        var size = 0;
        try {
          await for (final chunk in part) {
            size += chunk.length;
            total += chunk.length;
            if (total > maxBytes) {
              throw HttpError(413, 'Загрузка больше ${maxBytes ~/ (1024 * 1024)} МБ.');
            }
            sink.add(chunk);
          }
        } finally {
          await sink.close();
        }
        form.files[name] = UploadedFile(file, p.basename(filename), size);
      } else {
        final bytes = <int>[];
        await for (final chunk in part) {
          bytes.addAll(chunk);
          if (bytes.length > 1024 * 1024) throw HttpError(413, 'Поле «$name» слишком большое.');
        }
        form.fields[name] = utf8.decode(bytes, allowMalformed: true);
      }
    }
  } catch (_) {
    form.cleanup();
    rethrow;
  }
  return form;
}
