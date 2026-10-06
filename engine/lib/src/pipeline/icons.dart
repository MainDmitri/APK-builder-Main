import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../build_log.dart';

/// Generates Android launcher icons (legacy + adaptive) from a web/manifest
/// icon (PNG, JPEG, WebP, GIF, BMP or SVG) or, without one, a letter icon.
class LauncherIconGenerator {
  LauncherIconGenerator(this.log);

  final BuildLog log;

  static const Map<String, double> densities = {
    'mdpi': 1,
    'hdpi': 1.5,
    'xhdpi': 2,
    'xxhdpi': 3,
    'xxxhdpi': 4,
  };

  /// Writes icons into [resDir].
  ///
  /// [internalPrefix] namespaces the helper resources (foreground layer,
  /// background color) so they cannot clash with user resources.
  /// [launcherName] is the mipmap name of the icon (`<name>` and
  /// `<name>_round`); [writeLauncher] / [writeRound] control both files.
  Future<void> generate({
    required String resDir,
    required String? sourcePath,
    required String themeColor,
    required String label,
    String internalPrefix = '',
    String launcherName = 'ic_launcher',
    bool writeLauncher = true,
    bool writeRound = true,
  }) async {
    if (!writeLauncher && !writeRound) return;
    final tmp = await Directory.systemTemp.createTemp('appbuilder-icon');
    try {
      img.Image? source = sourcePath == null ? null : await _load(sourcePath, tmp.path);
      final theme = _parseColor(themeColor);
      img.ColorRgba8 background = theme;
      img.Image foregroundArt;
      double artScale;

      if (source != null) {
        source = _square(source.convert(format: img.Format.uint8, numChannels: 4));
        final corner = source.getPixel(0, 0);
        if (corner.a >= 250) background = img.ColorRgba8(corner.r.toInt(), corner.g.toInt(), corner.b.toInt(), 255);
        foregroundArt = source;
        artScale = 0.66;
        log.add('Иконка: ${p.basename(sourcePath!)} (${source.width}×${source.height}).');
      } else {
        foregroundArt = await _letter(label, theme, tmp.path);
        artScale = 1.0;
        log.add('Иконка не задана — сгенерирована буквенная иконка.');
      }

      final fgName = '${internalPrefix}ic_launcher_foreground';
      final bgName = '${internalPrefix}ic_launcher_background';
      for (final entry in densities.entries) {
        final dir = Directory(p.join(resDir, 'mipmap-${entry.key}'))..createSync(recursive: true);
        final fgSize = (108 * entry.value).round();
        final legacySize = (48 * entry.value).round();

        final foreground = img.Image(width: fgSize, height: fgSize, numChannels: 4);
        _drawCentered(foreground, foregroundArt, (fgSize * artScale).round());
        File(p.join(dir.path, '$fgName.png')).writeAsBytesSync(img.encodePng(foreground));

        // Legacy icons (Android 7.x): artwork on the background color.
        final legacy = img.Image(width: legacySize, height: legacySize, numChannels: 4);
        img.fill(legacy, color: background);
        _drawCentered(legacy, foregroundArt, (legacySize * (source != null ? 0.8 : 1.0)).round());
        if (writeLauncher) {
          File(p.join(dir.path, '$launcherName.png')).writeAsBytesSync(img.encodePng(_mask(legacy, round: false)));
        }
        if (writeRound) {
          File(p.join(dir.path, '${launcherName}_round.png')).writeAsBytesSync(img.encodePng(_mask(legacy, round: true)));
        }
      }

      final anydpi = Directory(p.join(resDir, 'mipmap-anydpi-v26'))..createSync(recursive: true);
      final adaptive = '''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/$bgName" />
    <foreground android:drawable="@mipmap/$fgName" />
</adaptive-icon>
''';
      if (writeLauncher) File(p.join(anydpi.path, '$launcherName.xml')).writeAsStringSync(adaptive);
      if (writeRound) File(p.join(anydpi.path, '${launcherName}_round.xml')).writeAsStringSync(adaptive);

      final values = Directory(p.join(resDir, 'values'))..createSync(recursive: true);
      File(p.join(values.path, '${internalPrefix}launcher_colors.xml')).writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="$bgName">${_hex(background)}</color>
</resources>
''');
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  Future<img.Image?> _load(String path, String tmpDir) async {
    final file = File(path);
    if (!file.existsSync()) {
      log.add('Иконка $path не найдена — будет сгенерирована буквенная.');
      return null;
    }
    if (p.extension(path).toLowerCase() == '.svg') {
      final png = await _rasterizeSvg(path, tmpDir, 1024);
      if (png == null) {
        log.add('Не удалось растеризовать SVG-иконку (нужен rsvg-convert) — будет сгенерирована буквенная.');
        return null;
      }
      return img.decodePng(png);
    }
    final decoded = img.decodeImage(file.readAsBytesSync());
    if (decoded == null) log.add('Формат иконки ${p.basename(path)} не поддерживается — будет сгенерирована буквенная.');
    return decoded;
  }

  Future<Uint8List?> _rasterizeSvg(String svgPath, String tmpDir, int size) async {
    final out = p.join(tmpDir, 'raster-${DateTime.now().microsecondsSinceEpoch}.png');
    try {
      final r = await Process.run('rsvg-convert', ['-w', '$size', '-h', '$size', '-a', '-o', out, svgPath]);
      if (r.exitCode != 0 || !File(out).existsSync()) return null;
      return File(out).readAsBytesSync();
    } on ProcessException {
      return null;
    }
  }

  /// Letter on a transparent 108dp canvas (adaptive foreground artwork).
  Future<img.Image> _letter(String label, img.ColorRgba8 background, String tmpDir) async {
    final match = RegExp(r'[\p{L}\p{N}]', unicode: true).firstMatch(label);
    final letter = (match?.group(0) ?? 'A').toUpperCase();
    final light = (0.299 * background.r + 0.587 * background.g + 0.114 * background.b) / 255 > 0.6;
    final textColor = light ? '#212121' : '#FFFFFF';
    final escaped = letter.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
    final svg = File(p.join(tmpDir, 'letter.svg'))
      ..writeAsStringSync('<svg xmlns="http://www.w3.org/2000/svg" width="432" height="432" viewBox="0 0 108 108">'
          '<text x="54" y="54" dy="0.35em" text-anchor="middle" font-family="DejaVu Sans, Arial, sans-serif" '
          'font-weight="bold" font-size="44" fill="$textColor">$escaped</text></svg>');
    final png = await _rasterizeSvg(svg.path, tmpDir, 432);
    if (png != null) {
      final decoded = img.decodePng(png);
      if (decoded != null) return decoded.convert(numChannels: 4);
    }
    // Fallback without librsvg: bitmap font (ASCII only), upscaled.
    final ascii = RegExp(r'[A-Za-z0-9]').firstMatch(label)?.group(0)?.toUpperCase() ?? 'A';
    final small = img.Image(width: 108, height: 108, numChannels: 4);
    final color = light ? img.ColorRgba8(33, 33, 33, 255) : img.ColorRgba8(255, 255, 255, 255);
    img.drawString(small, ascii, font: img.arial48, x: 54 - 14, y: 54 - 26, color: color);
    return img.copyResize(small, width: 432, height: 432, interpolation: img.Interpolation.cubic);
  }

  static img.Image _square(img.Image src) {
    if (src.width == src.height) return src;
    final size = math.max(src.width, src.height);
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    img.compositeImage(canvas, src, dstX: (size - src.width) ~/ 2, dstY: (size - src.height) ~/ 2);
    return canvas;
  }

  static void _drawCentered(img.Image canvas, img.Image art, int size) {
    final scaled = img.copyResize(art, width: size, height: size, interpolation: img.Interpolation.cubic);
    img.compositeImage(canvas, scaled, dstX: (canvas.width - size) ~/ 2, dstY: (canvas.height - size) ~/ 2);
  }

  /// Rounded-square (radius 20%) or circle mask with anti-aliased edges.
  static img.Image _mask(img.Image src, {required bool round}) {
    final out = src.clone();
    final size = src.width;
    final radius = round ? size / 2 : size * 0.2;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final cx = x + 0.5;
        final cy = y + 0.5;
        final nx = cx < radius ? radius : (cx > size - radius ? size - radius : cx);
        final ny = cy < radius ? radius : (cy > size - radius ? size - radius : cy);
        final dist = math.sqrt((cx - nx) * (cx - nx) + (cy - ny) * (cy - ny));
        final coverage = (radius - dist + 0.5).clamp(0.0, 1.0);
        if (coverage < 1.0) {
          final px = out.getPixel(x, y);
          out.setPixelRgba(x, y, px.r, px.g, px.b, (px.a * coverage).round());
        }
      }
    }
    return out;
  }

  static img.ColorRgba8 _parseColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', '').substring(0, 6), radix: 16) ?? 0x1565C0;
    return img.ColorRgba8((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF, 255);
  }

  static String _hex(img.ColorRgba8 c) =>
      '#${[c.r, c.g, c.b].map((v) => v.toInt().toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
}
