import 'templates.dart';

/// Edits top-level keys of an XML property list (Info.plist) without
/// touching the rest of the file: nested dictionaries and arrays are skipped
/// by depth, not by regular expressions.
abstract final class PlistEditor {
  static final _key = RegExp(r'<key>([^<]*)</key>');

  /// Range of the value of every top-level key and the position of the
  /// closing `</dict>` of the root dictionary.
  static ({Map<String, (int, int)> values, int end}) _scan(String plist) {
    final open = RegExp(r'<plist\b[^>]*>\s*<dict>').firstMatch(plist);
    if (open == null) throw const FormatException('Info.plist: нет корневого <dict>');
    final values = <String, (int, int)>{};
    var pos = open.end;
    while (true) {
      pos = _skipSpace(plist, pos);
      if (plist.startsWith('</dict>', pos)) return (values: values, end: pos);
      final key = _key.matchAsPrefix(plist, pos);
      if (key == null) throw FormatException('Info.plist: ожидался <key> на позиции $pos');
      final start = _skipSpace(plist, key.end);
      final end = _elementEnd(plist, start);
      values[key.group(1)!] = (start, end);
      pos = end;
    }
  }

  static int _skipSpace(String s, int pos) {
    while (true) {
      while (pos < s.length && ' \t\r\n'.contains(s[pos])) {
        pos++;
      }
      if (!s.startsWith('<!--', pos)) return pos;
      final close = s.indexOf('-->', pos);
      if (close < 0) throw const FormatException('Info.plist: незакрытый комментарий');
      pos = close + 3;
    }
  }

  /// End (exclusive) of the element that starts at [start].
  static int _elementEnd(String s, int start) {
    final tag = RegExp(r'<([A-Za-z]+)\s*(/?)>').matchAsPrefix(s, start);
    if (tag == null) throw FormatException('Info.plist: ожидалось значение на позиции $start');
    final name = tag.group(1)!;
    if (tag.group(2) == '/') return tag.end;
    if (name != 'dict' && name != 'array') {
      final close = s.indexOf('</$name>', tag.end);
      if (close < 0) throw FormatException('Info.plist: не закрыт <$name>');
      return close + name.length + 3;
    }
    var depth = 1;
    final nested = RegExp(r'<(/?)(dict|array)(\s*/)?>');
    for (final m in nested.allMatches(s, tag.end)) {
      if (m.group(3) != null) continue;
      depth += m.group(1)!.isEmpty ? 1 : -1;
      if (depth == 0) return m.end;
    }
    throw FormatException('Info.plist: не закрыт <$name>');
  }

  static bool hasKey(String plist, String key) => _scan(plist).values.containsKey(key);

  /// Sets [key] to [value] (string, bool, int, double, list or map),
  /// replacing the current value or adding the key at the end of the root dictionary.
  static String set(String plist, String key, Object value) {
    final scan = _scan(plist);
    final range = scan.values[key];
    if (range != null) return plist.replaceRange(range.$1, range.$2, encode(value, 1));
    return plist.replaceRange(scan.end, scan.end, '\t<key>${plistEscape(key)}</key>\n\t${encode(value, 1)}\n');
  }

  /// XML of a property list value; [indent] is the nesting level of the value.
  static String encode(Object value, [int indent = 0]) {
    final pad = '\t' * (indent + 1);
    final closePad = '\t' * indent;
    return switch (value) {
      String() => '<string>${plistEscape(value)}</string>',
      true => '<true/>',
      false => '<false/>',
      int() => '<integer>$value</integer>',
      double() => '<real>$value</real>',
      List() when value.isEmpty => '<array/>',
      List() => '<array>\n${value.map((v) => '$pad${encode(v as Object, indent + 1)}').join('\n')}\n$closePad</array>',
      Map() when value.isEmpty => '<dict/>',
      Map() => '<dict>\n${value.entries.map((e) => '$pad<key>${plistEscape('${e.key}')}</key>\n'
          '$pad${encode(e.value as Object, indent + 1)}').join('\n')}\n$closePad</dict>',
      _ => throw ArgumentError('Значение $value нельзя записать в Info.plist'),
    };
  }
}
