import 'package:flutter/services.dart';

import 'platform_info.dart';

class NativeException implements Exception {
  NativeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Android services implemented in MainActivity.kt: DownloadManager,
/// PackageInstaller sessions and the build status notification.
class NativeBridge {
  const NativeBridge();

  static const _channel = MethodChannel('net.appbuilder.app/native');
  static final Stream<Map<Object?, Object?>> _installEvents = const EventChannel('net.appbuilder.app/install')
      .receiveBroadcastStream()
      .map((event) => event as Map<Object?, Object?>);

  bool get available => isAndroidDevice;

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    if (!available) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw NativeException(e.message ?? e.code);
    }
  }

  /// Status notification calls never break the build flow.
  Future<void> _quiet(String method, [Map<String, Object?>? arguments]) async {
    try {
      await _call<void>(method, arguments);
    } on NativeException {
      // The notification is a convenience: e.g. Android may refuse to start
      // a foreground service; the build continues without it.
    }
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+. Returns true if granted.
  Future<bool> requestNotifications() async {
    try {
      return await _call<bool>('requestNotifications') ?? false;
    } on NativeException {
      return false;
    }
  }

  Future<void> watchStart(String title, String text) => _quiet('watchStart', {'title': title, 'text': text});

  /// [progress] 0..100, or null for an indeterminate bar.
  Future<void> watchUpdate(String title, String text, {int? progress}) =>
      _quiet('watchUpdate', {'title': title, 'text': text, 'progress': progress ?? -1});

  /// With a [title] a final dismissible notification is left.
  Future<void> watchStop({String? title, String? text}) => _quiet('watchStop', {'title': title, 'text': text});

  Future<String> downloadsDir() async => (await _call<String>('downloadsDir'))!;

  Future<int> enqueueDownload({
    required Uri url,
    required Map<String, String> headers,
    required String relativePath,
    required String title,
    required String tag,
  }) async =>
      (await _call<int>('downloadEnqueue', {
        'url': url.toString(),
        'headers': headers,
        'relativePath': relativePath,
        'title': title,
        'tag': tag,
      }))!;

  Future<Map<Object?, Object?>> queryDownload(int id) async =>
      (await _call<Map<Object?, Object?>>('downloadQuery', {'id': id})) ?? const {'status': 'missing'};

  Future<void> cancelDownload(int id) => _call<void>('downloadCancel', {'id': id});

  Future<bool> canInstall() async => await _call<bool>('canInstall') ?? false;

  Future<void> openInstallSettings() => _call<void>('openInstallSettings');

  Future<String?> apkPackageName(String path) => _call<String>('apkPackageName', {'path': path});

  /// Starts a PackageInstaller session; events arrive on [installEvents].
  Future<int> install(String path) async => (await _call<int>('install', {'path': path}))!;

  Stream<Map<Object?, Object?>> get installEvents => _installEvents;

  Future<bool> launch(String packageName) async => await _call<bool>('launch', {'packageName': packageName}) ?? false;
}
