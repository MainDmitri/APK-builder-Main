import 'dart:typed_data';

/// Web: APKs cannot be installed from a browser tab.
class ApkInstaller {
  const ApkInstaller();

  bool get isSupported => false;

  Future<String?> install(Uint8List bytes, String fileName) async => 'Установка доступна только в Android-версии приложения.';
}
