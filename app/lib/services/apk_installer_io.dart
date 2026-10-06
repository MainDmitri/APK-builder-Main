import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Android: writes the APK to the app cache and opens the system installer
/// (requires REQUEST_INSTALL_PACKAGES and "Install unknown apps" permission).
class ApkInstaller {
  const ApkInstaller();

  bool get isSupported => Platform.isAndroid;

  /// Returns an error message or null on success.
  Future<String?> install(Uint8List bytes, String fileName) async {
    if (!Platform.isAndroid) return 'Установка APK возможна только на Android.';
    final dir = Directory('${(await getTemporaryDirectory()).path}/apk')..createSync(recursive: true);
    for (final old in dir.listSync()) {
      old.deleteSync();
    }
    final file = File('${dir.path}/${fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}');
    await file.writeAsBytes(bytes, flush: true);
    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    return result.type == ResultType.done ? null : 'Не удалось открыть установщик: ${result.message}';
  }
}
