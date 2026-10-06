import 'dart:io';

/// Append-only build log kept in memory (for polling clients) and mirrored
/// to a file (for history and download).
class BuildLog {
  BuildLog(this.file, {this.echo = false}) {
    file.parent.createSync(recursive: true);
    _sink = file.openWrite(mode: FileMode.append);
  }

  /// Loads a finished log from disk (read-only).
  BuildLog.readOnly(this.file) : echo = false {
    if (file.existsSync()) _lines.addAll(file.readAsLinesSync());
  }

  final File file;

  /// Mirror lines to stdout (CLI mode).
  final bool echo;
  final List<String> _lines = [];
  IOSink? _sink;

  /// Secrets that must never appear in the log.
  final Set<String> _secrets = {};

  int get length => _lines.length;

  void addSecret(String value) {
    if (value.length >= 4) _secrets.add(value);
  }

  void add(String line) {
    var clean = line.replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), '').trimRight();
    for (final s in _secrets) {
      clean = clean.replaceAll(s, '******');
    }
    _lines.add(clean);
    _sink?.writeln(clean);
    if (echo) stdout.writeln(clean);
  }

  void section(String title) => add('━━━ $title ━━━');

  List<String> linesFrom(int index) =>
      index >= _lines.length ? const [] : _lines.sublist(index < 0 ? 0 : index);

  /// Last [count] lines — used to explain failures.
  List<String> tail(int count) => _lines.length <= count ? List.of(_lines) : _lines.sublist(_lines.length - count);

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }
}
