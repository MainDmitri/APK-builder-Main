import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend/build_backend.dart';
import '../../state/build_controller.dart';
import '../../state/settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/section_card.dart';
import 'build_progress.dart';
import 'icon_section.dart';
import 'signing_section.dart';

/// ZIP → analysis → parameters → signing → remote build → APK.
class BuildScreen extends StatelessWidget {
  const BuildScreen({super.key, required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BuildController>();
    final backend = context.watch<BuildBackend?>();
    final settings = context.watch<SettingsController>();
    final problems = c.readinessErrors(backend);
    final ready = problems.isEmpty && !c.submitting && !c.buildRunning && !c.analyzing;

    var order = 0;
    Widget entry(Widget child) => FadeSlideIn(delay: Duration(milliseconds: 70 * order++), child: child);

    return Scaffold(
      appBar: AppBar(title: const Text('Сборка APK')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              entry(const _Hero()),
              const SizedBox(height: 16),
              entry(_BackendCard(backend: backend, settings: settings, onOpenSettings: onOpenSettings)),
              const SizedBox(height: 16),
              entry(const _ProjectSection()),
              if (c.analysis?.canBuild ?? false) ...[
                const SizedBox(height: 16),
                const FadeSlideIn(child: _ParametersSection()),
                const SizedBox(height: 16),
                const FadeSlideIn(delay: Duration(milliseconds: 70), child: IconSection()),
                const SizedBox(height: 16),
                FadeSlideIn(delay: const Duration(milliseconds: 140), child: SigningSection(backend: backend)),
              ],
              const SizedBox(height: 20),
              entry(GradientButton(
                label: c.submitting ? 'Отправка проекта…' : (c.buildRunning ? 'Идёт сборка…' : 'Собрать APK'),
                icon: Icons.rocket_launch_rounded,
                loading: c.submitting || c.buildRunning,
                onPressed: ready ? () => c.startBuild(backend!) : null,
              )),
              if (problems.isNotEmpty && c.project != null) ...[
                const SizedBox(height: 8),
                MessageList(messages: problems, error: true),
              ],
              if (c.buildId != null || c.buildError != null) ...[
                const SizedBox(height: 16),
                FadeSlideIn(child: BuildProgressSection(backend: backend)),
              ],
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brand header of the build screen.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [AppColors.violet.withValues(alpha: 0.28), AppColors.cyan.withValues(alpha: 0.12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.violet.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const GradientBadge(icon: Icons.android, size: 52),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GradientText('AppBuilder', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text('Из ZIP — подписанный APK. Сборка в облаке, скачивание и установка прямо отсюда.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }
}

class _BackendCard extends StatelessWidget {
  const _BackendCard({required this.backend, required this.settings, required this.onOpenSettings});

  final BuildBackend? backend;
  final SettingsController settings;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (backend == null) {
      return Card(
        color: scheme.errorContainer,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Icon(Icons.cloud_off, color: scheme.onErrorContainer),
          title: Text('Сборщик не настроен', style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w700)),
          subtitle: Text(
            'Укажите адрес своего AppBuilder Engine или репозиторий GitHub для сборки через Actions.',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
          trailing: FilledButton(onPressed: onOpenSettings, child: const Text('Настроить')),
        ),
      );
    }
    final target = settings.mode == BackendMode.engine
        ? settings.engineUrl
        : '${settings.githubOwner}/${settings.githubRepo}${settings.githubBranch.isEmpty ? '' : ' @ ${settings.githubBranch}'}';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: GradientBadge(icon: settings.mode == BackendMode.engine ? Icons.dns : Icons.cloud_sync, size: 36),
        title: Text(settings.mode.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(target),
        trailing: IconButton(icon: const Icon(Icons.tune), tooltip: 'Настройки', onPressed: onOpenSettings),
      ),
    );
  }
}

class _ProjectSection extends StatelessWidget {
  const _ProjectSection();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BuildController>();
    final project = c.project;
    final analysis = c.analysis;
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Проект (ZIP)',
      icon: Icons.folder_zip_outlined,
      trailing: project == null ? null : IconButton(icon: const Icon(Icons.close), tooltip: 'Убрать', onPressed: c.clearProject),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (project == null) ...[
            const Text('Веб-проект (index.html), Node.js-проект (package.json: React, Vue, Vite…) '
                'или Android-исходники (AndroidManifest.xml, Kotlin/Java). Файлы — в корне архива.'),
            const SizedBox(height: 12),
          ] else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.archive_outlined),
              title: Text(project.name),
              subtitle: Text(formatBytes(project.bytes.length)),
            ),
          OutlinedButton.icon(
            onPressed: c.analyzing || c.buildRunning ? null : c.pickProject,
            icon: const Icon(Icons.upload_file),
            label: Text(project == null ? 'Выбрать ZIP' : 'Выбрать другой ZIP'),
          ),
          if (c.analyzing) const Padding(padding: EdgeInsets.only(top: 12), child: GradientProgressBar(value: null, height: 6)),
          if (c.projectError != null) ...[
            const SizedBox(height: 12),
            MessageList(messages: [c.projectError!], error: true),
          ],
          if (analysis != null) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                avatar: Icon(analysis.canBuild ? Icons.check_circle : Icons.cancel,
                    color: analysis.canBuild ? AppColors.success : theme.colorScheme.error),
                label: Text(analysis.kind.title),
              ),
              Chip(label: Text('Файлов: ${analysis.fileCount}')),
              if (analysis.node != null) ...[
                Chip(label: Text(analysis.node!.packageManager.id)),
                Chip(label: Text(analysis.node!.framework)),
              ],
              if (analysis.native?.usesCompose ?? false) const Chip(label: Text('Jetpack Compose')),
              if (analysis.native != null && !(analysis.native!.usesKotlin)) const Chip(label: Text('Java')),
            ]),
            if (analysis.node != null)
              _kv(context, 'Команды', '${analysis.node!.installCommand.join(' ')}  →  ${analysis.node!.buildCommand.join(' ')}'),
            if (analysis.native?.mainActivity != null) _kv(context, 'LAUNCHER', analysis.native!.mainActivity!),
            if (analysis.canBuild) ...[
              const SizedBox(height: 8),
              Text('Этапы сборки', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final (i, stage) in analysis.plan.stages.indexed) Text('${i + 1}. ${stage.title}'),
            ],
            if (analysis.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              MessageList(messages: analysis.errors, error: true),
            ],
            if (analysis.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              MessageList(messages: analysis.warnings, error: false),
            ],
          ],
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String key, String value) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$key: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: value, style: const TextStyle(fontFamily: 'monospace')),
        ])),
      );
}

class _ParametersSection extends StatelessWidget {
  const _ParametersSection();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BuildController>();
    if (c.isNativeGradle) {
      return const SectionCard(
        title: 'Параметры приложения',
        icon: Icons.tune,
        child: Text('Gradle-проект: название, пакет, версия и разрешения берутся из build.gradle и '
            'AndroidManifest.xml самого проекта.'),
      );
    }
    final available = c.isWeb ? AppPermission.values.where(AppPermission.webSupported.contains) : AppPermission.values;
    return SectionCard(
      title: 'Параметры приложения',
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: c.appName,
            onChanged: (_) => c.changed(),
            decoration: InputDecoration(labelText: 'Название', errorText: Validators.appName(c.appName.text)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c.packageName,
            onChanged: (_) => c.changed(),
            decoration: InputDecoration(
              labelText: 'Имя пакета (applicationId)',
              hintText: 'com.example.app',
              errorText: Validators.packageName(c.packageName.text),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: c.versionName,
                onChanged: (_) => c.changed(),
                decoration: InputDecoration(labelText: 'Версия', errorText: Validators.versionName(c.versionName.text)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: c.versionCode,
                onChanged: (_) => c.changed(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'versionCode', errorText: Validators.versionCode(c.versionCode.text)),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text('Ориентация экрана', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<ScreenOrientation>(
            segments: [
              for (final o in ScreenOrientation.values) ButtonSegment(value: o, label: Text(o.title)),
            ],
            selected: {c.orientation},
            onSelectionChanged: (s) => c.setOrientation(s.first),
          ),
          const SizedBox(height: 16),
          Text('Разрешения', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in available)
              FilterChip(
                label: Text(p.title),
                selected: c.permissions.contains(p),
                onSelected: (v) => c.togglePermission(p, v),
              ),
          ]),
          if (c.analysis?.kind == ProjectKind.nativeSources)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Отмеченные разрешения будут добавлены в AndroidManifest.xml, если их там нет.'),
            ),
        ],
      ),
    );
  }
}
