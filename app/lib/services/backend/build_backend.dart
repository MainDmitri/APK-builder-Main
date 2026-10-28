import 'dart:typed_data';

import 'package:appbuilder_core/appbuilder_core.dart';

/// Where APKs are built: a self-hosted AppBuilder Engine or GitHub Actions.
enum BackendMode {
  engine('Свой сервер (AppBuilder Engine)'),
  github('GitHub Actions (без сервера)');

  const BackendMode(this.title);

  final String title;
}

class BackendException implements Exception {
  BackendException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BackendInfo {
  const BackendInfo({required this.ok, required this.message, this.details = const {}});

  final bool ok;
  final String message;
  final Map<String, String> details;
}

class KeystoreInput {
  const KeystoreInput({
    required this.bytes,
    required this.fileName,
    required this.storePassword,
    required this.alias,
    required this.keyPassword,
  });

  final Uint8List bytes;
  final String fileName;
  final String storePassword;
  final String alias;
  final String keyPassword;
}

class KeystoreValidation {
  const KeystoreValidation({
    required this.valid,
    this.error,
    this.aliases = const [],
    this.owner,
    this.sha256,
    this.validUntil,
  });

  final bool valid;
  final String? error;
  final List<String> aliases;
  final String? owner;
  final String? sha256;
  final String? validUntil;
}

class BuildSubmission {
  const BuildSubmission({
    required this.projectZip,
    required this.projectFileName,
    required this.options,
    this.keystore,
    this.icon,
    this.iconFileName,
    this.ios = false,
  });

  final Uint8List projectZip;
  final String projectFileName;
  final BuildOptions options;
  final KeystoreInput? keystore;

  /// Launcher icon picture that replaces the project's own icon.
  final Uint8List? icon;
  final String? iconFileName;

  /// Also build an unsigned .ipa for iPhone (GitHub Actions, web projects).
  final bool ios;

  /// `icon.png` / `icon.jpg` / `icon.webp` for the uploaded picture.
  String get iconUploadName {
    final name = (iconFileName ?? '').toLowerCase();
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
    return 'icon${const ['.png', '.jpg', '.jpeg', '.webp'].contains(ext) ? ext : '.png'}';
  }
}

enum RemoteBuildState { queued, running, succeeded, failed }

enum IosBuildState { pending, succeeded, failed }

/// The iPhone part of a build (unsigned .ipa compiled on macOS).
class IosBuildInfo {
  const IosBuildInfo({required this.state, this.fileName, this.size, this.error});

  final IosBuildState state;
  final String? fileName;
  final int? size;
  final String? error;
}

class RemoteBuildStatus {
  const RemoteBuildStatus({
    required this.state,
    this.stageTitle,
    this.stages = const [],
    this.currentStage,
    this.logLines = const [],
    this.nextLogIndex = 0,
    this.error,
    this.apkFileName,
    this.apkSize,
    this.apkSha256,
    this.signingSchemes = const [],
    this.warnings = const [],
    this.detailsUrl,
    this.queuePosition,
    this.ios,
  });

  final RemoteBuildState state;
  final String? stageTitle;

  /// Titles of all pipeline stages (empty when the backend does not report them).
  final List<String> stages;

  /// Index of the running stage in [stages].
  final int? currentStage;

  /// New log lines since the requested index.
  final List<String> logLines;
  final int nextLogIndex;
  final String? error;
  final String? apkFileName;
  final int? apkSize;
  final String? apkSha256;
  final List<String> signingSchemes;
  final List<String> warnings;

  /// Web page with details (GitHub Actions run / release).
  final String? detailsUrl;
  final int? queuePosition;

  /// Present when the build also produces an .ipa for iPhone.
  final IosBuildInfo? ios;

  /// The APK part is done.
  bool get isFinished => state == RemoteBuildState.succeeded || state == RemoteBuildState.failed;

  bool get iosPending => ios?.state == IosBuildState.pending;
}

class RemoteBuildSummary {
  const RemoteBuildSummary({
    required this.id,
    required this.state,
    required this.title,
    required this.createdAt,
    this.apkFileName,
    this.ipaFileName,
    this.detailsUrl,
  });

  final String id;
  final RemoteBuildState state;
  final String title;
  final DateTime createdAt;
  final String? apkFileName;
  final String? ipaFileName;
  final String? detailsUrl;
}

/// Files a build produces.
enum ArtifactKind {
  apk('application/vnd.android.package-archive', 'APK'),
  ipa('application/octet-stream', 'IPA');

  const ArtifactKind(this.mimeType, this.label);

  final String mimeType;
  final String label;
}

/// Where a file of a finished build is downloaded from.
class ArtifactSource {
  const ArtifactSource({
    required this.url,
    required this.fileName,
    this.headers = const {},
    this.size,
    this.kind = ArtifactKind.apk,
  });

  final Uri url;
  final String fileName;
  final ArtifactKind kind;

  /// Request headers (authorization of a self-hosted engine).
  final Map<String, String> headers;

  /// Expected size in bytes, when the backend knows it.
  final int? size;
}

/// Common interface of both build backends.
abstract interface class BuildBackend {
  BackendMode get mode;

  /// Production keystores can be uploaded (engine) or come from repository
  /// secrets (GitHub).
  bool get supportsKeystoreUpload;

  /// iPhone builds need macOS: available with GitHub Actions only.
  bool get supportsIos;

  /// Recommended polling interval for [status].
  Duration get pollInterval;

  Future<BackendInfo> checkConnection();

  Future<KeystoreValidation> validateKeystore(KeystoreInput keystore);

  /// Returns the build id.
  Future<String> submit(BuildSubmission submission);

  Future<RemoteBuildStatus> status(String id, {int logFrom = 0});

  /// Download address of the APK or IPA of a successful build.
  Future<ArtifactSource> artifactSource(String id, ArtifactKind kind);

  Future<List<RemoteBuildSummary>> history();

  void close();
}
