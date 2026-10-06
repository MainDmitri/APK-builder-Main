import 'analysis.dart';
import 'models.dart';
import 'project_source.dart';
import 'toolchain.dart';

/// Result of inspecting a directory that is served as the web root.
class WebRootInfo {
  const WebRootInfo({this.manifest, this.manifestPath, this.iconPath});

  final WebManifest? manifest;

  /// Manifest path relative to the web root.
  final String? manifestPath;

  /// Best launcher icon candidate relative to the web root.
  final String? iconPath;
}

/// Launcher icon that the project itself provides.
class ProjectIcon {
  const ProjectIcon(this.path, {this.predicted = false});

  /// Path inside the archive.
  final String path;

  /// Node.js projects: the icon is taken from the build output, so this is
  /// the source file it is expected to come from (`public/…`).
  final bool predicted;

  /// PNG / JPEG / WebP / GIF / BMP (can be previewed as a picture).
  bool get isRaster => RegExp(r'\.(png|jpe?g|webp|gif|bmp)$', caseSensitive: false).hasMatch(path);
}

/// Detects what kind of project an archive contains and how to build it.
///
/// Priority (as required by the AppBuilder contract):
///   1. `package.json` in the root  → Node.js project (two-stage build);
///   2. `index.html` in the root    → static web;
///   3. Gradle / AndroidManifest.xml / .java / .kt → native Android.
class ProjectAnalyzer {
  const ProjectAnalyzer();

  static const _ignoredSegments = {'__MACOSX', '.git', '.idea', '.gradle', '.vscode', '.svn'};
  static const _ignoredNames = {'.DS_Store', 'Thumbs.db', 'desktop.ini'};

  static bool isIgnored(String path) {
    final segments = path.split('/');
    if (segments.any(_ignoredSegments.contains)) return true;
    return _ignoredNames.contains(segments.last);
  }

  /// Finds a wrapper directory shared by every file (e.g. the archive
  /// contains only `my-app/...`). Strips at most three levels.
  static String detectRootPrefix(Iterable<String> files) {
    var prefix = '';
    for (var depth = 0; depth < 3; depth++) {
      String? first;
      var single = true;
      for (final f in files) {
        final rest = f.substring(prefix.length);
        final slash = rest.indexOf('/');
        if (slash < 0) {
          single = false;
          break;
        }
        final seg = rest.substring(0, slash);
        if (first == null) {
          first = seg;
        } else if (first != seg) {
          single = false;
          break;
        }
      }
      if (!single || first == null) break;
      prefix = '$prefix$first/';
    }
    return prefix;
  }

  ProjectAnalysis analyze(ProjectFileSource source) {
    final all = source.paths.map((p) => p.replaceAll('\\', '/')).where((p) => !isIgnored(p)).toList()..sort();
    if (all.isEmpty) {
      return const ProjectAnalysis(
        kind: ProjectKind.unsupported,
        rootPrefix: '',
        fileCount: 0,
        errors: ['Архив пуст.'],
      );
    }
    return _analyzeAt(source, all, detectRootPrefix(all));
  }

  /// Analyzes the archive with [prefix] as the project root. [nestedNote] is
  /// set when the root was found automatically inside a subfolder.
  ProjectAnalysis _analyzeAt(
    ProjectFileSource source,
    List<String> all,
    String prefix, {
    String? nestedNote,
    String? fallbackConfig,
  }) {
    final ctx = _Ctx(
      source,
      prefix,
      all.where((p) => p.startsWith(prefix)).map((p) => p.substring(prefix.length)).toSet(),
      nestedNote: nestedNote,
    );

    if (source.symlinks.isNotEmpty) {
      ctx.warnings.add('Символические ссылки не поддерживаются и будут пропущены: ${_preview(source.symlinks)}.');
    }
    final keystores = ctx.files.where((f) => RegExp(r'\.(jks|keystore|p12|pfx)$').hasMatch(f)).toList();
    if (keystores.isNotEmpty) {
      ctx.warnings.add('В архиве есть файлы ключей (${_preview(keystores)}). Они не используются: '
          'подпись выбирается в настройках сборки. Не храните ключи в архиве.');
    }

    final configText = ctx.has('appbuilder.json')
        ? ctx.read('appbuilder.json')
        : (fallbackConfig == null ? null : source.readText(fallbackConfig));
    if (configText != null) ctx.config = AppBuilderConfig.parse(configText, ctx.errors, ctx.warnings);

    if (ctx.has('package.json') && !_nodeFallsBackToStatic(ctx)) return _analyzeNode(ctx);
    if (ctx.has('index.html')) return _analyzeStatic(ctx);

    if (nestedNote == null) {
      // Android project in a subfolder (e.g. android/settings.gradle).
      final gradleRoot = _shallowestDir(ctx.files, (name) => name == 'settings.gradle' || name == 'settings.gradle.kts');
      if (gradleRoot != null && gradleRoot.isNotEmpty) {
        return _analyzeAt(source, all, '$prefix$gradleRoot/',
            nestedNote: _nestedNote(ctx.files, gradleRoot, 'Android-проект (settings.gradle)'),
            fallbackConfig: ctx.has('appbuilder.json') ? '${prefix}appbuilder.json' : null);
      }
      if (gradleRoot != null || ctx.files.any((f) => f.endsWith('AndroidManifest.xml') && !_isVendored(f))) {
        return _analyzeNative(ctx);
      }
      // Web project in a subfolder: client/, frontend/, web/ …
      final nested = _findNestedWebProject(ctx);
      if (nested != null) {
        return _analyzeAt(source, all, '$prefix$nested/',
            nestedNote: _nestedNote(ctx.files, nested, 'веб-проект'),
            fallbackConfig: ctx.has('appbuilder.json') ? '${prefix}appbuilder.json' : null);
      }
    }

    if (_hasNativeMarkers(ctx.files)) return _analyzeNative(ctx);

    final top = ctx.files.map((f) => f.contains('/') ? '${f.substring(0, f.indexOf('/'))}/' : f).toSet().toList()..sort();
    ctx.errors.add('Не найдено ни веб-проекта (package.json со скриптом build или index.html), ни Android-проекта '
        '(settings.gradle, AndroidManifest.xml, .kt/.java). Содержимое архива: ${_preview(top)}.');
    return ctx.build(ProjectKind.unsupported);
  }

  static const _preferredWebDirs = [
    'client', 'frontend', 'front', 'web', 'webapp', 'www', 'app', 'site', 'ui', 'public', 'dist', 'build',
  ];
  static const _unlikelyWebDirs = {'server', 'backend', 'api', 'functions', 'docs', 'doc', 'test', 'tests', 'examples'};

  static bool _isVendored(String path) =>
      path.contains('node_modules/') || path.contains('/build/') || path.startsWith('build/');

  /// Shallowest directory containing a file whose name matches [test].
  static String? _shallowestDir(Set<String> files, bool Function(String name) test) {
    String? best;
    for (final f in files) {
      if (_isVendored(f)) continue;
      final slash = f.lastIndexOf('/');
      final name = f.substring(slash + 1);
      if (!test(name)) continue;
      final dir = slash < 0 ? '' : f.substring(0, slash);
      if (best == null || dir.split('/').length < best.split('/').length || (dir.isEmpty && best.isNotEmpty)) {
        best = dir;
      }
    }
    return best;
  }

  /// Finds a subfolder with a buildable web project: package.json with a
  /// "build" script (preferred) or index.html. Shallow folders and typical
  /// frontend names (client, frontend, web…) win.
  String? _findNestedWebProject(_Ctx ctx) {
    final candidates = <String, int>{}; // dir → 0 (Node project) | 1 (static)
    for (final f in ctx.files) {
      if (_isVendored(f) || !f.contains('/')) continue;
      final dir = f.substring(0, f.lastIndexOf('/'));
      final name = f.substring(f.lastIndexOf('/') + 1);
      if (name == 'package.json') {
        final pkg = _readJsonMap(ctx, f, report: false);
        final scripts = pkg?['scripts'];
        final build = scripts is Map ? scripts['build'] : null;
        if ((build is String && build.trim().isNotEmpty) || ctx.has('$dir/index.html')) candidates[dir] = 0;
      } else if (name == 'index.html') {
        candidates.putIfAbsent(dir, () => 1);
      }
    }
    if (candidates.isEmpty) return null;
    int rank(String dir) {
      final top = dir.split('/').first.toLowerCase();
      final preferred = _preferredWebDirs.indexOf(top);
      if (preferred >= 0) return preferred;
      return _unlikelyWebDirs.contains(top) ? 200 : 100;
    }

    final dirs = candidates.keys.toList()
      ..sort((a, b) {
        final depth = a.split('/').length.compareTo(b.split('/').length);
        if (depth != 0) return depth;
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        final t = candidates[a]!.compareTo(candidates[b]!);
        return t != 0 ? t : a.compareTo(b);
      });
    return dirs.first;
  }

  static String _nestedNote(Set<String> files, String dir, String what) {
    final others = files
        .where((f) => !f.startsWith('$dir/') && f != 'appbuilder.json')
        .map((f) => f.contains('/') ? '${f.substring(0, f.indexOf('/'))}/' : f)
        .where((top) => '$dir/'.startsWith(top) == false)
        .toSet()
        .toList()
      ..sort();
    return 'В корне архива нет package.json и index.html — найден $what в папке «$dir/», она собирается как корень проекта.'
        '${others.isEmpty ? '' : ' Остальное (${_preview(others)}) в APK не попадёт.'}';
  }

  // ---------------------------------------------------------------- Node.js

  bool _nodeFallsBackToStatic(_Ctx ctx) {
    if (!ctx.has('index.html')) return false;
    final pkg = _readJsonMap(ctx, 'package.json', report: false);
    final scripts = pkg?['scripts'];
    final build = scripts is Map ? scripts['build'] : null;
    if (build is String && build.trim().isNotEmpty) return false;
    ctx.warnings.add('package.json без скрипта "build", а index.html лежит в корне — '
        'проект упакован как статический веб без этапа npm.');
    return true;
  }

  ProjectAnalysis _analyzeNode(_Ctx ctx) {
    final pkg = _readJsonMap(ctx, 'package.json', report: true);
    if (pkg == null) return ctx.build(ProjectKind.nodeProject);

    final scripts = pkg['scripts'] is Map ? pkg['scripts'] as Map : const {};
    final buildScript = scripts['build'] is String ? (scripts['build'] as String).trim() : '';
    if (buildScript.isEmpty) {
      ctx.errors.add('В package.json нет скрипта "build". Добавьте, например: "build": "vite build".');
    }

    final deps = <String>{
      if (pkg['dependencies'] is Map) ...(pkg['dependencies'] as Map).keys.cast<String>(),
      if (pkg['devDependencies'] is Map) ...(pkg['devDependencies'] as Map).keys.cast<String>(),
    };

    // Package manager: "packageManager" field, then lockfiles.
    PackageManager pm = PackageManager.npm;
    final pmField = pkg['packageManager'];
    if (pmField is String && pmField.startsWith('pnpm@')) {
      pm = PackageManager.pnpm;
    } else if (pmField is String && pmField.startsWith('yarn@')) {
      pm = PackageManager.yarn;
    } else if (pmField is String && pmField.startsWith('bun@')) {
      ctx.warnings.add('Bun не поддерживается движком — используется npm.');
    } else if (ctx.has('pnpm-lock.yaml')) {
      pm = PackageManager.pnpm;
    } else if (ctx.has('yarn.lock')) {
      pm = PackageManager.yarn;
    } else if (ctx.has('bun.lockb') || ctx.has('bun.lock')) {
      ctx.warnings.add('Найден lock-файл Bun — Bun не поддерживается, используется npm.');
    }
    final hasLockfile = switch (pm) {
      PackageManager.npm => ctx.has('package-lock.json') || ctx.has('npm-shrinkwrap.json'),
      PackageManager.yarn => ctx.has('yarn.lock'),
      PackageManager.pnpm => ctx.has('pnpm-lock.yaml'),
    };

    final framework = _detectFramework(deps, buildScript);
    final candidates = <String>[];
    final declared = ctx.config?.outputDir;
    if (declared != null) candidates.add(_cleanRelative(declared));

    switch (framework) {
      case 'vite':
        final config = _firstExisting(ctx, _viteConfigs);
        final text = config == null ? null : ctx.read(config);
        final outDir = text == null ? null : RegExp(r'''outDir\s*:\s*['"]([^'"]+)['"]''').firstMatch(text)?.group(1);
        if (outDir != null) candidates.add(_cleanRelative(outDir));
        candidates.add('dist');
        final baseOk = buildScript.contains('--base') ||
            (text != null && RegExp(r'''base\s*:\s*['"]\.\/?['"]''').hasMatch(text));
        if (!baseOk) {
          ctx.warnings.add('Vite: не задан base: \'./\' в vite.config. Оболочка AppBuilder отдаёт файлы '
              'из корня, поэтому сборка заработает, но по контракту укажите base: \'./\'.');
        }
      case 'cra':
        candidates.add('build');
      case 'next':
        candidates.add('out');
        final config = _firstExisting(ctx, const ['next.config.js', 'next.config.mjs', 'next.config.ts']);
        final text = config == null ? null : ctx.read(config);
        if (text == null || !RegExp(r'''output\s*:\s*['"]export['"]''').hasMatch(text)) {
          ctx.warnings.add('Next.js: для статической сборки нужен output: \'export\' в next.config '
              '(иначе папка out/ не появится и сборка APK завершится ошибкой).');
        }
      case 'angular':
        candidates.addAll(_angularOutputs(ctx, pkg['name'] as String?));
      case 'nuxt':
        candidates.addAll(['.output/public', 'dist']);
        if (!buildScript.contains('generate')) {
          ctx.warnings.add('Nuxt: используйте "build": "nuxt generate" — серверная сборка не подходит для APK.');
        }
      case 'sveltekit':
        candidates.add('build');
        if (!deps.contains('@sveltejs/adapter-static')) {
          ctx.warnings.add('SvelteKit: нужен @sveltejs/adapter-static для статической сборки.');
        }
      case 'vue-cli' || 'astro' || 'parcel':
        candidates.add('dist');
      case 'webpack':
        candidates.addAll(['dist', 'build']);
    }
    for (final generic in const ['dist', 'build', 'out', 'www']) {
      if (!candidates.contains(generic)) candidates.add(generic);
    }

    if (ctx.files.any((f) => f.startsWith('node_modules/'))) {
      ctx.warnings.add('Папка node_modules в архиве будет удалена перед установкой зависимостей '
          '(не добавляйте её в ZIP).');
    }

    // Web manifest is usually in public/ and copied into the output dir.
    for (final m in const ['public/manifest.json', 'public/manifest.webmanifest', 'public/site.webmanifest']) {
      if (ctx.has(m)) {
        final text = ctx.read(m);
        if (text != null) {
          ctx.manifest = WebManifest.parse(text, ctx.warnings, m);
          ctx.manifestPath = m;
        }
        break;
      }
    }

    ctx.node = NodeProjectInfo(
      packageManager: pm,
      hasLockfile: hasLockfile,
      buildScript: buildScript,
      framework: framework,
      outputDirCandidates: candidates,
      packageName: pkg['name'] as String?,
      packageVersion: pkg['version'] as String?,
    );
    return ctx.build(ProjectKind.nodeProject);
  }

  static const _viteConfigs = [
    'vite.config.ts',
    'vite.config.js',
    'vite.config.mts',
    'vite.config.mjs',
    'vite.config.cts',
    'vite.config.cjs',
  ];

  String _detectFramework(Set<String> deps, String buildScript) {
    if (deps.contains('next') || buildScript.contains('next build')) return 'next';
    if (deps.contains('nuxt') || buildScript.contains('nuxt')) return 'nuxt';
    if (deps.contains('@sveltejs/kit')) return 'sveltekit';
    if (deps.contains('astro')) return 'astro';
    if (deps.contains('@angular/core') || buildScript.contains('ng build')) return 'angular';
    if (deps.contains('react-scripts') || buildScript.contains('react-scripts')) return 'cra';
    if (deps.contains('@vue/cli-service')) return 'vue-cli';
    if (deps.contains('vite') || buildScript.contains('vite')) return 'vite';
    if (deps.contains('parcel') || buildScript.contains('parcel')) return 'parcel';
    if (deps.contains('webpack') || buildScript.contains('webpack')) return 'webpack';
    return 'unknown';
  }

  List<String> _angularOutputs(_Ctx ctx, String? packageName) {
    final out = <String>[];
    final angular = _readJsonMap(ctx, 'angular.json', report: false);
    final projects = angular?['projects'];
    if (projects is Map && projects.isNotEmpty) {
      for (final entry in projects.entries) {
        final outputPath = _jsonPath(entry.value, ['architect', 'build', 'options', 'outputPath']) ??
            _jsonPath(entry.value, ['targets', 'build', 'options', 'outputPath']);
        final base = switch (outputPath) {
          final String s => s,
          final Map m when m['base'] is String => m['base'] as String,
          _ => 'dist/${entry.key}',
        };
        out.addAll(['${_cleanRelative(base)}/browser', _cleanRelative(base)]);
      }
    }
    if (packageName != null) out.addAll(['dist/$packageName/browser', 'dist/$packageName']);
    return out;
  }

  // ------------------------------------------------------------- Static web

  ProjectAnalysis _analyzeStatic(_Ctx ctx) {
    final info = inspectWebRoot(ctx.files, ctx.read, ctx.warnings);
    ctx.manifest = info.manifest;
    ctx.manifestPath = info.manifestPath;
    ctx.indexHtml = 'index.html';
    return ctx.build(ProjectKind.staticWeb);
  }

  /// Inspects a web root (static project or Node build output): web
  /// manifest, icons and contract violations in HTML files.
  static WebRootInfo inspectWebRoot(Set<String> files, String? Function(String) read, List<String> warnings) {
    final indexText = read('index.html') ?? '';

    String? manifestPath;
    final link = RegExp(r'''<link\b[^>]*\brel\s*=\s*["']?manifest["']?[^>]*>''', caseSensitive: false)
        .firstMatch(indexText);
    if (link != null) {
      final href = RegExp(r'''href\s*=\s*["']([^"']+)["']''', caseSensitive: false).firstMatch(link.group(0)!);
      final value = href?.group(1);
      if (value != null && !value.contains('://')) {
        final clean = _cleanRelative(value.split('?').first.split('#').first);
        if (files.contains(clean)) manifestPath = clean;
      }
    }
    manifestPath ??= const ['manifest.json', 'manifest.webmanifest', 'site.webmanifest'].where(files.contains).firstOrNull;

    WebManifest? manifest;
    String? iconPath;
    if (manifestPath != null) {
      final text = read(manifestPath);
      if (text != null) manifest = WebManifest.parse(text, warnings, manifestPath);
      if (manifest != null) {
        final dir = manifestPath.contains('/') ? manifestPath.substring(0, manifestPath.lastIndexOf('/') + 1) : '';
        final icons = [...manifest.icons]..sort((a, b) => b.maxEdge.compareTo(a.maxEdge));
        for (final icon in icons) {
          if (icon.src.contains('://') || icon.src.startsWith('data:')) continue;
          final resolved = icon.src.startsWith('/') ? _cleanRelative(icon.src) : _cleanRelative('$dir${icon.src}');
          if (files.contains(resolved)) {
            iconPath ??= resolved;
          } else {
            warnings.add('Иконка «${icon.src}» из $manifestPath отсутствует в архиве.');
          }
        }
        if (manifest.name == null && manifest.shortName == null) {
          warnings.add('$manifestPath: нет поля name — название берётся из настроек сборки.');
        }
      }
    }
    iconPath ??= const ['icon.png', 'icon.svg', 'icons/icon-512.png', 'favicon.png', 'apple-touch-icon.png']
        .where(files.contains)
        .firstOrNull;

    final absolute = <String>{};
    final cleartext = <String>{};
    final htmlFiles = files.where((f) => f.endsWith('.html') || f.endsWith('.htm')).take(30);
    final absRe = RegExp(r'''\b(?:src|href)\s*=\s*["'](/(?!/)[^"'\s>]*)["']''', caseSensitive: false);
    final httpRe = RegExp(r'''\b(?:src|href)\s*=\s*["'](http://[^"'\s>]+)["']''', caseSensitive: false);
    for (final f in htmlFiles) {
      final text = read(f);
      if (text == null) continue;
      for (final m in absRe.allMatches(text)) {
        absolute.add('$f: ${m.group(1)}');
      }
      for (final m in httpRe.allMatches(text)) {
        cleartext.add(m.group(1)!);
      }
    }
    if (absolute.isNotEmpty) {
      warnings.add('Абсолютные пути вместо относительных (${_preview(absolute.toList())}). '
          'Оболочка AppBuilder отдаёт файлы из корня, поэтому они сработают, но по контракту '
          'используйте ./путь.');
    }
    if (cleartext.isNotEmpty) {
      warnings.add('Ресурсы по http:// (${_preview(cleartext.toList())}) заблокированы Android — используйте https://.');
    }
    return WebRootInfo(manifest: manifest, manifestPath: manifestPath, iconPath: iconPath);
  }

  /// Icon the engine uses when no picture is chosen at build time, or null
  /// when it will generate a letter icon.
  static ProjectIcon? findProjectIcon(ProjectAnalysis analysis, ProjectFileSource source) {
    final prefix = analysis.rootPrefix;
    final paths = source.paths.map((f) => f.replaceAll('\\', '/')).toList();

    ProjectIcon? web(String base, {bool predicted = false}) {
      final files = {for (final f in paths) if (f.startsWith(base)) f.substring(base.length)};
      final info = inspectWebRoot(files, (rel) => source.readText('$base$rel'), []);
      return info.iconPath == null ? null : ProjectIcon('$base${info.iconPath}', predicted: predicted);
    }

    switch (analysis.kind) {
      case ProjectKind.staticWeb:
        return web(prefix);
      case ProjectKind.nodeProject:
        return web('${prefix}public/', predicted: true);
      case ProjectKind.nativeSources:
      case ProjectKind.nativeGradle:
        final manifestPath = analysis.native?.manifestPath;
        final String name;
        if (manifestPath == null) {
          name = 'ic_launcher';
        } else {
          final manifest = source.readText('$prefix$manifestPath') ?? '';
          final tag = RegExp(r'<application\b[^>]*>', dotAll: true).firstMatch(manifest)?.group(0) ?? '';
          final icon = RegExp(r'android:icon\s*=\s*"@(?:mipmap|drawable)/([A-Za-z0-9_]+)"').firstMatch(tag)?.group(1);
          if (icon == null) return null;
          name = icon;
        }
        const densities = ['xxxhdpi', 'xxhdpi', 'xhdpi', 'hdpi', 'mdpi', ''];
        final candidates = paths.where((f) =>
            f.startsWith(prefix) &&
            RegExp('(^|/)res/(mipmap|drawable)(-[a-z0-9-]+)?/${RegExp.escape(name)}\\.(png|webp|jpe?g|xml)\$').hasMatch(f));
        int rank(String f) {
          if (f.endsWith('.xml')) return densities.length + 1;
          final i = densities.indexWhere((d) => d.isNotEmpty && f.contains('-$d/'));
          return i < 0 ? densities.length : i;
        }
        final sorted = candidates.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
        return sorted.isEmpty ? null : ProjectIcon(sorted.first);
      case ProjectKind.unsupported:
        return null;
    }
  }

  // ----------------------------------------------------------------- Native

  static bool _hasNativeMarkers(Set<String> files) => files.any((f) =>
      f.endsWith('settings.gradle') ||
      f.endsWith('settings.gradle.kts') ||
      f.endsWith('build.gradle') ||
      f.endsWith('build.gradle.kts') ||
      f.endsWith('AndroidManifest.xml') ||
      f.endsWith('.kt') ||
      f.endsWith('.java'));

  ProjectAnalysis _analyzeNative(_Ctx ctx) {
    final settings = _firstExisting(ctx, const ['settings.gradle.kts', 'settings.gradle']);
    if (settings != null) return _analyzeGradleProject(ctx, settings);
    return _analyzeSources(ctx);
  }

  ProjectAnalysis _analyzeGradleProject(_Ctx ctx, String settingsPath) {
    final settings = ctx.read(settingsPath) ?? '';
    final modules = <String>[];
    for (final line in RegExp(r'^\s*include\b(.*)$', multiLine: true).allMatches(settings)) {
      for (final q in RegExp(r'''["']:?([\w\-:.]+)["']''').allMatches(line.group(1)!)) {
        modules.add(q.group(1)!.replaceAll(':', '/'));
      }
    }

    String? buildFileOf(String module) {
      final base = module.isEmpty ? '' : '$module/';
      return _firstExisting(ctx, ['${base}build.gradle.kts', '${base}build.gradle']);
    }

    String? appModule;
    for (final m in [...modules, '']) {
      final bf = buildFileOf(m);
      final text = bf == null ? null : ctx.read(bf);
      if (text != null && (text.contains('com.android.application') || text.contains('android.application'))) {
        appModule = m;
        break;
      }
    }
    if (appModule == null && modules.contains('app')) appModule = 'app';
    if (appModule == null) {
      ctx.errors.add('Gradle-проект: не найден модуль приложения с плагином com.android.application.');
      ctx.native = const NativeProjectInfo(gradleProject: true);
      return ctx.build(ProjectKind.nativeGradle);
    }

    final hasWrapperScript = ctx.has('gradlew');
    final hasWrapperJar = ctx.has('gradle/wrapper/gradle-wrapper.jar');
    final wrapperProps = ctx.read('gradle/wrapper/gradle-wrapper.properties');
    final wrapperVersion = wrapperProps == null
        ? null
        : RegExp(r'gradle-([0-9][\w.\-]*?)-(?:bin|all)\.zip').firstMatch(wrapperProps)?.group(1);
    final usableWrapper = hasWrapperScript && hasWrapperJar && wrapperProps != null;
    if (!usableWrapper) {
      ctx.warnings.add('Gradle Wrapper неполный (нужны gradlew, gradle/wrapper/gradle-wrapper.jar и .properties) — '
          'используется Gradle ${Toolchain.gradle} движка. Плагин Android Gradle в проекте должен быть совместим с ним '
          '(рекомендуется AGP ${Toolchain.androidGradlePlugin}).');
    }

    final moduleBase = appModule.isEmpty ? '' : '$appModule/';
    final buildFile = buildFileOf(appModule);
    final buildText = buildFile == null ? '' : (ctx.read(buildFile) ?? '');
    if (RegExp(r'signingConfigs\s*\{').hasMatch(buildText)) {
      ctx.warnings.add('В $buildFile объявлены signingConfigs — если они ссылаются на отсутствующий keystore, '
          'сборка упадёт. Удалите их: движок сам подписывает APK.');
    }
    if (ctx.has('local.properties')) {
      ctx.warnings.add('local.properties будет перезаписан путём к Android SDK движка.');
    }

    final manifestPath = '${moduleBase}src/main/AndroidManifest.xml';
    final manifest = ctx.read(manifestPath);
    var hasLauncher = false;
    String? mainActivity;
    final namespace = _gradleString(buildText, 'namespace');
    final applicationId = _gradleString(buildText, 'applicationId') ?? namespace;
    if (manifest == null) {
      ctx.errors.add('Нет файла $manifestPath.');
    } else {
      hasLauncher = manifest.contains('android.intent.category.LAUNCHER');
      mainActivity = _launcherActivity(manifest, namespace ?? _manifestPackage(manifest));
      if (!hasLauncher) {
        ctx.warnings.add('В $manifestPath нет активности с MAIN/LAUNCHER — приложение не появится в лаунчере.');
      }
    }

    final sources = ctx.files.where((f) => f.startsWith(moduleBase) && (f.endsWith('.kt') || f.endsWith('.java')));
    ctx.native = NativeProjectInfo(
      gradleProject: true,
      appModule: appModule,
      hasUsableWrapper: usableWrapper,
      wrapperGradleVersion: wrapperVersion,
      manifestPath: manifestPath,
      namespace: namespace,
      applicationId: applicationId,
      mainActivity: mainActivity,
      label: manifest == null ? null : _appLabel(ctx, manifest, '${moduleBase}src/main'),
      usesKotlin: sources.any((f) => f.endsWith('.kt')),
      usesCompose: buildText.contains('compose'),
      hasLauncher: hasLauncher,
    );
    return ctx.build(ProjectKind.nativeGradle);
  }

  ProjectAnalysis _analyzeSources(_Ctx ctx) {
    final manifests = ctx.files.where((f) => f.endsWith('AndroidManifest.xml') && !f.contains('/build/')).toList()
      ..sort((a, b) {
        final am = a.endsWith('src/main/AndroidManifest.xml') ? 0 : 1;
        final bm = b.endsWith('src/main/AndroidManifest.xml') ? 0 : 1;
        return am != bm ? am.compareTo(bm) : a.length.compareTo(b.length);
      });

    final kotlinPackageRe = RegExp(r'^\s*package\s+([A-Za-z_][\w.]*)', multiLine: true);

    if (manifests.isEmpty) return _analyzeLooseSources(ctx, kotlinPackageRe);

    final manifestPath = manifests.first;
    if (manifests.length > 1) {
      ctx.warnings.add('Найдено несколько AndroidManifest.xml — используется $manifestPath.');
    }
    final root = manifestPath.contains('/') ? manifestPath.substring(0, manifestPath.lastIndexOf('/')) : '';
    final rootBase = root.isEmpty ? '' : '$root/';
    final sources = ctx.files
        .where((f) =>
            (f.startsWith('${rootBase}java/') || f.startsWith('${rootBase}kotlin/')) &&
            (f.endsWith('.kt') || f.endsWith('.java')))
        .toList();
    if (sources.isEmpty) {
      ctx.errors.add('Нет исходников: ожидаются файлы .kt/.java в ${rootBase}java/<пакет>/.');
    }

    final manifest = ctx.read(manifestPath) ?? '';
    var namespace = _manifestPackage(manifest);
    if (namespace != null) {
      ctx.warnings.add('Атрибут package в AndroidManifest.xml будет удалён: пакет задаётся через namespace.');
    }
    final hasLauncher = manifest.contains('android.intent.category.LAUNCHER');
    if (!hasLauncher) {
      ctx.errors.add('В $manifestPath нет активности с intent-filter MAIN / LAUNCHER.');
    }

    // Namespace fallback: package of the launcher activity source file.
    final launcherName = _launcherActivityRaw(manifest);
    if (namespace == null) {
      final simple = launcherName?.split('.').last;
      final file = sources.firstWhere(
        (f) => simple != null && (f.endsWith('/$simple.kt') || f.endsWith('/$simple.java')),
        orElse: () => sources.isEmpty ? '' : sources.first,
      );
      final text = file.isEmpty ? null : ctx.read(file);
      namespace = text == null ? null : kotlinPackageRe.firstMatch(text)?.group(1);
      if (namespace == null && sources.isNotEmpty) {
        ctx.errors.add('Не удалось определить пакет: добавьте объявление package в $file.');
      }
    }

    // Dependencies from a module build file shipped next to src/main.
    final declared = <String>[];
    if (root.endsWith('src/main')) {
      final moduleDir = root.substring(0, root.length - 'src/main'.length);
      final bf = _firstExisting(ctx, ['${moduleDir}build.gradle.kts', '${moduleDir}build.gradle']);
      final text = bf == null ? null : ctx.read(bf);
      if (text != null) {
        final re = RegExp(r'''(?:implementation|api)\s*\(?\s*["']([^"'$:\s]+:[^"'$:\s]+:[^"'$\s]+)["']''');
        declared.addAll(re.allMatches(text).map((m) => m.group(1)!));
        ctx.warnings.add('$bf игнорируется (Gradle-файлы генерирует движок). '
            'Найдено зависимостей с явной версией: ${declared.length}; они будут подключены. '
            'Остальные укажите в appbuilder.json → android.dependencies.');
      }
    }

    final kotlinSources = sources.where((f) => f.endsWith('.kt')).toList();
    final usesCompose = ctx.config?.compose ??
        kotlinSources.any((f) => ctx.read(f)?.contains('androidx.compose') ?? false);

    ctx.native = NativeProjectInfo(
      gradleProject: false,
      sourceSetRoot: root,
      manifestPath: manifestPath,
      namespace: namespace,
      applicationId: namespace,
      mainActivity: launcherName == null || namespace == null ? null : _qualify(launcherName, namespace),
      label: _appLabel(ctx, manifest, root),
      usesKotlin: kotlinSources.isNotEmpty,
      usesCompose: usesCompose,
      hasLauncher: hasLauncher,
      declaredDependencies: declared,
    );
    return ctx.build(ProjectKind.nativeSources);
  }

  ProjectAnalysis _analyzeLooseSources(_Ctx ctx, RegExp packageRe) {
    final sources = ctx.files
        .where((f) => (f.endsWith('.kt') || f.endsWith('.java')) && !f.contains('/build/'))
        .toList();
    if (sources.isEmpty) {
      ctx.errors.add('Найдены Gradle-файлы, но нет settings.gradle, AndroidManifest.xml и исходников .kt/.java.');
      ctx.native = const NativeProjectInfo(gradleProject: false);
      return ctx.build(ProjectKind.unsupported);
    }
    final ktActivity = RegExp(
        r'class\s+(\w+)\s*(?:\([^)]*\))?\s*:\s*(?:[\w.]+\.)?(?:AppCompatActivity|ComponentActivity|FragmentActivity|Activity)\s*\(');
    final javaActivity =
        RegExp(r'class\s+(\w+)\s+extends\s+(?:[\w.]+\.)?(?:AppCompatActivity|ComponentActivity|FragmentActivity|Activity)\b');
    String? activityFile;
    String? activityName;
    for (final f in [...sources]..sort((a, b) => (a.contains('MainActivity') ? 0 : 1) - (b.contains('MainActivity') ? 0 : 1))) {
      final text = ctx.read(f) ?? '';
      final m = (f.endsWith('.kt') ? ktActivity : javaActivity).firstMatch(text);
      if (m != null) {
        activityFile = f;
        activityName = m.group(1);
        break;
      }
    }
    String? namespace;
    if (activityFile == null) {
      ctx.errors.add('Не найден AndroidManifest.xml и класс Activity (MainActivity). '
          'Добавьте app/src/main/AndroidManifest.xml с LAUNCHER-активностью.');
    } else {
      namespace = packageRe.firstMatch(ctx.read(activityFile) ?? '')?.group(1);
      if (namespace == null) ctx.errors.add('В $activityFile нет объявления package.');
      ctx.warnings.add('AndroidManifest.xml не найден — манифест будет сгенерирован автоматически '
          '(LAUNCHER: $activityName). Исходники разложены по пакетам из их объявлений package.');
    }
    final kotlin = sources.where((f) => f.endsWith('.kt'));
    ctx.native = NativeProjectInfo(
      gradleProject: false,
      namespace: namespace,
      applicationId: namespace,
      mainActivity: namespace == null || activityName == null ? null : '$namespace.$activityName',
      usesKotlin: kotlin.isNotEmpty,
      usesCompose: ctx.config?.compose ?? kotlin.any((f) => ctx.read(f)?.contains('androidx.compose') ?? false),
      hasLauncher: activityFile != null,
      looseSources: sources,
      looseResources: ctx.files.where((f) => f.startsWith('res/') || f.contains('/res/')).toList(),
    );
    return ctx.build(ProjectKind.nativeSources);
  }

  // ---------------------------------------------------------------- helpers

  /// `android:label` of `<application>`; `@string/x` is looked up in
  /// `<sourceSet>/res/values/strings.xml`.
  static String? _appLabel(_Ctx ctx, String manifest, String sourceSetRoot) {
    final app = RegExp(r'<application\b[^>]*>', dotAll: true).firstMatch(manifest)?.group(0);
    final raw = app == null ? null : RegExp(r'android:label\s*=\s*"([^"]+)"').firstMatch(app)?.group(1);
    if (raw == null) return null;
    if (!raw.startsWith('@string/')) return raw;
    final base = sourceSetRoot.isEmpty ? '' : '$sourceSetRoot/';
    final strings = ctx.read('${base}res/values/strings.xml');
    final name = RegExp.escape(raw.substring('@string/'.length));
    final value = strings == null ? null : RegExp('<string\\s+name="$name"[^>]*>([^<]*)</string>').firstMatch(strings)?.group(1);
    return value?.replaceAll(r"\'", "'").replaceAll(r'\"', '"').trim();
  }

  static String? _manifestPackage(String manifest) =>
      RegExp(r'<manifest\b[^>]*\bpackage\s*=\s*"([^"]+)"', dotAll: true).firstMatch(manifest)?.group(1);

  static String? _launcherActivityRaw(String manifest) {
    final re = RegExp(r'<activity\b([^>]*)>(.*?)</activity>', dotAll: true);
    for (final m in re.allMatches(manifest)) {
      if (m.group(2)!.contains('android.intent.category.LAUNCHER')) {
        return RegExp(r'android:name\s*=\s*"([^"]+)"').firstMatch(m.group(1)!)?.group(1);
      }
    }
    return null;
  }

  static String? _launcherActivity(String manifest, String? namespace) {
    final raw = _launcherActivityRaw(manifest);
    if (raw == null) return null;
    return namespace == null ? raw : _qualify(raw, namespace);
  }

  static String _qualify(String name, String namespace) {
    if (name.startsWith('.')) return '$namespace$name';
    if (!name.contains('.')) return '$namespace.$name';
    return name;
  }

  static Object? _jsonPath(Object? node, List<String> keys) {
    var current = node;
    for (final k in keys) {
      if (current is! Map) return null;
      current = current[k];
    }
    return current;
  }

  static String? _gradleString(String text, String key) =>
      RegExp('\\b$key\\s*=?\\s*["\']([\\w.]+)["\']').firstMatch(text)?.group(1);

  static String? _firstExisting(_Ctx ctx, List<String> candidates) {
    for (final c in candidates) {
      if (ctx.has(c)) return c;
    }
    return null;
  }

  static Map<dynamic, dynamic>? _readJsonMap(_Ctx ctx, String path, {required bool report}) {
    final text = ctx.read(path);
    if (text == null) {
      if (report) ctx.errors.add('Не удалось прочитать $path.');
      return null;
    }
    try {
      final decoded = jsonDecodeLenient(text);
      if (decoded is Map) return decoded;
      if (report) ctx.errors.add('$path: корень должен быть JSON-объектом.');
    } on FormatException catch (e) {
      if (report) ctx.errors.add('$path: некорректный JSON (${e.message}).');
    }
    return null;
  }

  static String _cleanRelative(String path) {
    var p = path.trim().replaceAll('\\', '/');
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  static String _preview(List<String> items) {
    final shown = items.take(5).join(', ');
    return items.length > 5 ? '$shown и ещё ${items.length - 5}' : shown;
  }
}

class _Ctx {
  _Ctx(this.source, this.prefix, this.files, {this.nestedNote});

  final ProjectFileSource source;
  final String prefix;
  final Set<String> files;
  final String? nestedNote;
  final List<String> errors = [];
  final List<String> warnings = [];
  AppBuilderConfig? config;
  WebManifest? manifest;
  String? manifestPath;
  NodeProjectInfo? node;
  NativeProjectInfo? native;
  String? indexHtml;

  bool has(String path) => files.contains(path);

  String? read(String path) => files.contains(path) ? source.readText('$prefix$path') : null;

  ProjectAnalysis build(ProjectKind kind) {
    if (nestedNote != null) {
      warnings.insert(0, nestedNote!);
    } else if (prefix.isNotEmpty && kind != ProjectKind.nativeSources) {
      warnings.insert(
          0,
          'Файлы лежат во вложенной папке «$prefix» — она использована как корень. '
          'По контракту содержимое должно лежать прямо в корне ZIP.');
    }
    return ProjectAnalysis(
      kind: kind,
      rootPrefix: prefix,
      fileCount: files.length,
      errors: List.unmodifiable(errors),
      warnings: List.unmodifiable(warnings),
      config: config,
      manifest: manifest,
      manifestPath: manifestPath,
      node: node,
      native: native,
      indexHtml: indexHtml,
    );
  }
}
