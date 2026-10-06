/// Input validation shared by the Flutter client and the engine.
/// Every validator returns `null` when the value is valid, otherwise a
/// human-readable error message.
abstract final class Validators {
  static final RegExp _segment = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

  static const Set<String> _javaKeywords = {
    'abstract', 'assert', 'boolean', 'break', 'byte', 'case', 'catch', 'char', 'class', 'const',
    'continue', 'default', 'do', 'double', 'else', 'enum', 'extends', 'final', 'finally', 'float',
    'for', 'goto', 'if', 'implements', 'import', 'instanceof', 'int', 'interface', 'long', 'native',
    'new', 'package', 'private', 'protected', 'public', 'return', 'short', 'static', 'strictfp',
    'super', 'switch', 'synchronized', 'this', 'throw', 'throws', 'transient', 'try', 'void',
    'volatile', 'while', 'true', 'false', 'null', 'var', 'record', 'yield',
    // Kotlin hard keywords
    'as', 'fun', 'in', 'is', 'object', 'typealias', 'typeof', 'val', 'when',
  };

  static String? packageName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Укажите имя пакета, например com.example.app';
    if (v.length > 150) return 'Имя пакета слишком длинное';
    final parts = v.split('.');
    if (parts.length < 2) return 'Нужно минимум два сегмента: com.example';
    for (final p in parts) {
      if (!_segment.hasMatch(p)) {
        return 'Сегмент «$p»: только латиница, цифры и _, начинается с буквы';
      }
      if (_javaKeywords.contains(p)) return 'Сегмент «$p» — зарезервированное слово Java/Kotlin';
    }
    return null;
  }

  static String? appName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Укажите название приложения';
    if (v.length > 50) return 'Не длиннее 50 символов';
    return null;
  }

  static String? versionName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Укажите версию, например 1.0.0';
    if (!RegExp(r'^[0-9A-Za-z][0-9A-Za-z.\-+_]{0,63}$').hasMatch(v)) {
      return 'Допустимы цифры, буквы, точки и дефисы (1.0.0)';
    }
    return null;
  }

  static String? versionCode(String? value) {
    final n = int.tryParse(value?.trim() ?? '');
    if (n == null) return 'Целое число';
    if (n < 1 || n > 2100000000) return 'Диапазон 1 … 2100000000';
    return null;
  }

  static String? hexColor(String? value) {
    final v = value?.trim() ?? '';
    if (!RegExp(r'^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(v)) {
      return 'Цвет в формате #RRGGBB';
    }
    return null;
  }

  /// keytool rejects store/key passwords shorter than 6 characters.
  static String? keystorePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Введите пароль';
    if (v.length < 6) return 'Минимум 6 символов (требование keytool)';
    return null;
  }

  static String? keyAlias(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Введите alias ключа';
    return null;
  }

  /// Checks the magic bytes of a keystore file: JKS (FEEDFEED), JCEKS
  /// (CECECECE) or PKCS#12 (DER SEQUENCE, 0x30).
  static String? keystoreBytes(List<int> head) {
    if (head.length < 4) return 'Файл keystore пуст или повреждён';
    final isJks = head[0] == 0xFE && head[1] == 0xED && head[2] == 0xFE && head[3] == 0xED;
    final isJceks = head[0] == 0xCE && head[1] == 0xCE && head[2] == 0xCE && head[3] == 0xCE;
    final isPkcs12 = head[0] == 0x30;
    if (!isJks && !isJceks && !isPkcs12) {
      return 'Это не keystore: ожидается JKS, JCEKS или PKCS12 (.jks / .keystore / .p12)';
    }
    return null;
  }

  /// Makes a valid package segment out of arbitrary text.
  static String packageSegmentFrom(String text) {
    final ascii = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    var seg = ascii.replaceFirst(RegExp(r'^[0-9]+'), '');
    if (seg.isEmpty) seg = 'app';
    if (_javaKeywords.contains(seg)) seg = '${seg}app';
    return seg.length > 40 ? seg.substring(0, 40) : seg;
  }
}
