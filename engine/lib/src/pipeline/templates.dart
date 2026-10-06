import 'dart:io';

import 'package:path/path.dart' as p;

import '../workspace.dart';

/// Copies a template directory and substitutes `{{KEY}}` placeholders in
/// text files. Fails loudly if a placeholder is left unresolved.
abstract final class TemplateRenderer {
  static const _textExtensions = {'.kts', '.xml', '.properties', '.java', '.gradle', '.json'};
  static final _placeholder = RegExp(r'\{\{([A-Z0-9_]+)\}\}');

  static void render(String templateDir, String targetDir, Map<String, String> values) {
    if (!Directory(templateDir).existsSync()) {
      throw StateError('Шаблон не найден: $templateDir (проверьте APPBUILDER_TEMPLATES).');
    }
    copyDirectory(templateDir, targetDir);
    for (final f in Directory(targetDir).listSync(recursive: true).whereType<File>()) {
      if (!_textExtensions.contains(p.extension(f.path))) continue;
      final source = f.readAsStringSync();
      if (!source.contains('{{')) continue;
      final rendered = source.replaceAllMapped(_placeholder, (m) {
        final key = m.group(1)!;
        final value = values[key];
        if (value == null) throw StateError('Нет значения для {{$key}} в ${p.relative(f.path, from: targetDir)}');
        return value;
      });
      f.writeAsStringSync(rendered);
    }
  }
}

/// Escapes text for an Android `<string>` resource.
String androidStringEscape(String value) {
  var s = value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');
  if (s.startsWith('@') || s.startsWith('?')) s = '\\$s';
  return s;
}

/// Safe Gradle `rootProject.name`.
String gradleProjectName(String packageName) {
  final last = packageName.split('.').last.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '');
  return last.isEmpty ? 'app' : last;
}
