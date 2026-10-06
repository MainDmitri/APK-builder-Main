enum TransferPhase { queued, downloading, paused, done, failed }

/// Download progress of one APK.
class TransferUpdate {
  const TransferUpdate(this.phase, {this.received = 0, this.total, this.message, this.path});

  final TransferPhase phase;
  final int received;
  final int? total;

  /// Pause reason or error text.
  final String? message;

  /// Local file once [phase] is [TransferPhase.done] (null on the web).
  final String? path;
}

enum InstallPhase { needsPermission, preparing, confirm, installing, installed, failed }

/// Progress of installing a downloaded APK.
class InstallUpdate {
  const InstallUpdate(this.phase, {this.progress, this.message, this.packageName});

  final InstallPhase phase;

  /// 0..1 while the APK is copied into the installer session.
  final double? progress;
  final String? message;
  final String? packageName;
}
