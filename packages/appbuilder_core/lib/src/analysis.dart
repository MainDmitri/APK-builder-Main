import 'models.dart';

enum PackageManager {
  npm('npm'),
  yarn('yarn'),
  pnpm('pnpm');

  const PackageManager(this.id);

  final String id;
}

/// Details of a `package.json` project.
class NodeProjectInfo {
  const NodeProjectInfo({
    required this.packageManager,
    required this.hasLockfile,
    required this.buildScript,
    required this.framework,
    required this.outputDirCandidates,
    this.packageName,
    this.packageVersion,
  });

  final PackageManager packageManager;
  final bool hasLockfile;
  final String buildScript;

  /// vite, cra, next, angular, vue-cli, sveltekit, astro, nuxt, parcel,
  /// webpack or `unknown`.
  final String framework;

  /// Directories (relative to project root) that may contain the built
  /// `index.html`, most likely first.
  final List<String> outputDirCandidates;

  final String? packageName;
  final String? packageVersion;

  /// Shell command line used to install dependencies.
  List<String> get installCommand => switch (packageManager) {
        PackageManager.npm => hasLockfile
            ? ['npm', 'ci', '--no-audit', '--no-fund']
            : ['npm', 'install', '--no-audit', '--no-fund'],
        PackageManager.yarn => ['yarn', 'install'],
        PackageManager.pnpm => ['pnpm', 'install', '--no-frozen-lockfile'],
      };

  List<String> get buildCommand => switch (packageManager) {
        PackageManager.npm => ['npm', 'run', 'build'],
        PackageManager.yarn => ['yarn', 'run', 'build'],
        PackageManager.pnpm => ['pnpm', 'run', 'build'],
      };

  Map<String, Object?> toJson() => {
        'packageManager': packageManager.id,
        'hasLockfile': hasLockfile,
        'buildScript': buildScript,
        'framework': framework,
        'outputDirCandidates': outputDirCandidates,
        'installCommand': installCommand.join(' '),
        'buildCommand': buildCommand.join(' '),
      };
}

/// Details of a native Android project.
class NativeProjectInfo {
  const NativeProjectInfo({
    required this.gradleProject,
    this.appModule,
    this.hasUsableWrapper = false,
    this.wrapperGradleVersion,
    this.sourceSetRoot,
    this.manifestPath,
    this.namespace,
    this.applicationId,
    this.mainActivity,
    this.usesKotlin = false,
    this.usesCompose = false,
    this.hasLauncher = false,
    this.declaredDependencies = const [],
    this.looseSources = const [],
    this.looseResources = const [],
  });

  /// `true` for a complete Gradle project (settings.gradle present).
  final bool gradleProject;

  /// Application module directory (Gradle project), e.g. `app`.
  final String? appModule;
  final bool hasUsableWrapper;
  final String? wrapperGradleVersion;

  /// Sources mode: directory holding AndroidManifest.xml, java/, res/ …
  /// (`''`, `src/main` or `app/src/main`). `null` for loose sources.
  final String? sourceSetRoot;
  final String? manifestPath;

  /// Package of the generated `R` class.
  final String? namespace;
  final String? applicationId;

  /// Fully qualified launcher activity class name.
  final String? mainActivity;
  final bool usesKotlin;
  final bool usesCompose;
  final bool hasLauncher;

  /// Literal `group:artifact:version` dependencies found in a module
  /// build.gradle shipped next to the sources.
  final List<String> declaredDependencies;

  /// Loose mode (no manifest): every .kt/.java file.
  final List<String> looseSources;

  /// Loose mode: files below a `res/` directory.
  final List<String> looseResources;

  Map<String, Object?> toJson() => {
        'gradleProject': gradleProject,
        if (appModule != null) 'appModule': appModule,
        'hasUsableWrapper': hasUsableWrapper,
        if (wrapperGradleVersion != null) 'wrapperGradleVersion': wrapperGradleVersion,
        if (sourceSetRoot != null) 'sourceSetRoot': sourceSetRoot,
        if (manifestPath != null) 'manifestPath': manifestPath,
        if (namespace != null) 'namespace': namespace,
        if (applicationId != null) 'applicationId': applicationId,
        if (mainActivity != null) 'mainActivity': mainActivity,
        'usesKotlin': usesKotlin,
        'usesCompose': usesCompose,
        'hasLauncher': hasLauncher,
        'declaredDependencies': declaredDependencies,
        if (looseSources.isNotEmpty) 'looseSources': looseSources,
      };
}

/// Result of [ProjectAnalyzer.analyze].
class ProjectAnalysis {
  const ProjectAnalysis({
    required this.kind,
    required this.rootPrefix,
    required this.fileCount,
    this.errors = const [],
    this.warnings = const [],
    this.config,
    this.manifest,
    this.manifestPath,
    this.node,
    this.native,
    this.indexHtml,
  });

  final ProjectKind kind;

  /// Top-level folder that was treated as the project root (`''` if none).
  final String rootPrefix;
  final int fileCount;

  /// Blocking problems — the build will not be started.
  final List<String> errors;

  /// Non-blocking problems.
  final List<String> warnings;

  final AppBuilderConfig? config;
  final WebManifest? manifest;

  /// Path of the web manifest relative to the web root.
  final String? manifestPath;
  final NodeProjectInfo? node;
  final NativeProjectInfo? native;

  /// Web root entry point (relative to the web root).
  final String? indexHtml;

  bool get canBuild => kind != ProjectKind.unsupported && errors.isEmpty;

  BuildPlan get plan => BuildPlan.forKind(kind);

  Map<String, Object?> toJson() => {
        'kind': kind.id,
        'kindTitle': kind.title,
        'rootPrefix': rootPrefix,
        'fileCount': fileCount,
        'canBuild': canBuild,
        'errors': errors,
        'warnings': warnings,
        if (manifest != null) 'manifest': manifest!.toJson(),
        if (manifestPath != null) 'manifestPath': manifestPath,
        if (node != null) 'node': node!.toJson(),
        if (native != null) 'native': native!.toJson(),
        'plan': plan.stages.map((s) => s.title).toList(),
      };
}

enum BuildStage {
  extract('Распаковка и анализ архива'),
  nodeInstall('Установка зависимостей (npm / yarn / pnpm)'),
  nodeBuild('Сборка веб-проекта (run build)'),
  webAssets('Копирование веб-ассетов в WebView-оболочку'),
  androidProject('Генерация Android-проекта'),
  gradle('Gradle assembleRelease'),
  zipalign('zipalign -p 4'),
  sign('apksigner: подпись v1 + v2 + v3'),
  verify('apksigner verify');

  const BuildStage(this.title);

  final String title;
}

/// Ordered pipeline stages for a project kind (two-stage pipeline for
/// Node.js projects: web build first, then Android packaging).
class BuildPlan {
  const BuildPlan(this.stages);

  final List<BuildStage> stages;

  static const _signing = [BuildStage.zipalign, BuildStage.sign, BuildStage.verify];

  factory BuildPlan.forKind(ProjectKind kind) => switch (kind) {
        ProjectKind.nodeProject => const BuildPlan([
            BuildStage.extract,
            BuildStage.nodeInstall,
            BuildStage.nodeBuild,
            BuildStage.webAssets,
            BuildStage.androidProject,
            BuildStage.gradle,
            ..._signing,
          ]),
        ProjectKind.staticWeb => const BuildPlan([
            BuildStage.extract,
            BuildStage.webAssets,
            BuildStage.androidProject,
            BuildStage.gradle,
            ..._signing,
          ]),
        ProjectKind.nativeSources => const BuildPlan([
            BuildStage.extract,
            BuildStage.androidProject,
            BuildStage.gradle,
            ..._signing,
          ]),
        ProjectKind.nativeGradle => const BuildPlan([
            BuildStage.extract,
            BuildStage.gradle,
            ..._signing,
          ]),
        ProjectKind.unsupported => const BuildPlan([BuildStage.extract]),
      };
}
