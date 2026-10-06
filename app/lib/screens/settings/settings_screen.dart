import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend/build_backend.dart';
import '../../state/settings_controller.dart';
import '../../widgets/section_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsController _settings = context.read<SettingsController>();
  late final _engineUrl = TextEditingController(text: _settings.engineUrl);
  late final _engineToken = TextEditingController(text: _settings.engineToken);
  late final _owner = TextEditingController(text: _settings.githubOwner);
  late final _repo = TextEditingController(text: _settings.githubRepo);
  late final _branch = TextEditingController(text: _settings.githubBranch);
  late final _githubToken = TextEditingController(text: _settings.githubToken);
  bool _checking = false;
  BackendInfo? _info;
  String? _error;

  @override
  void dispose() {
    for (final c in [_engineUrl, _engineToken, _owner, _repo, _branch, _githubToken]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveAndCheck() async {
    if (_settings.mode == BackendMode.engine) {
      final uri = Uri.tryParse(_engineUrl.text.trim());
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
        setState(() => _error = 'Адрес вида http://192.168.1.10:8080 или https://builder.example.com');
        return;
      }
      await _settings.saveEngine(url: _engineUrl.text, token: _engineToken.text);
    } else {
      await _settings.saveGithub(owner: _owner.text, repo: _repo.text, branch: _branch.text, token: _githubToken.text);
    }
    final backend = _settings.createBackend();
    if (backend == null) {
      setState(() => _error = 'Заполните обязательные поля');
      return;
    }
    setState(() {
      _checking = true;
      _info = null;
      _error = null;
    });
    try {
      final info = await backend.checkConnection();
      setState(() => _info = info);
    } on BackendException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Ошибка: $e');
    } finally {
      backend.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'Где собирать APK',
                icon: Icons.precision_manufacturing_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<BackendMode>(
                      segments: const [
                        ButtonSegment(value: BackendMode.engine, icon: Icon(Icons.dns), label: Text('Свой сервер')),
                        ButtonSegment(value: BackendMode.github, icon: Icon(Icons.cloud_sync), label: Text('GitHub Actions')),
                      ],
                      selected: {s.mode},
                      onSelectionChanged: (v) {
                        s.setMode(v.first);
                        setState(() {
                          _info = null;
                          _error = null;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (s.mode == BackendMode.engine) ..._engineFields() else ..._githubFields(),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _checking ? null : _saveAndCheck,
                      icon: _checking
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.wifi_tethering),
                      label: const Text('Сохранить и проверить подключение'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      MessageList(messages: [_error!], error: true),
                    ],
                    if (_info != null) ...[
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_info!.ok ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: _info!.ok ? Colors.green : const Color(0xFFB26A00)),
                        title: Text(_info!.message),
                        subtitle: _info!.details.isEmpty
                            ? null
                            : Text(_info!.details.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SectionCard(
                title: 'Оформление',
                icon: Icons.palette_outlined,
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('Системная')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
                  ],
                  selected: {s.themeMode},
                  onSelectionChanged: (v) => s.setThemeMode(v.first),
                ),
              ),
              const SizedBox(height: 16),
              const SectionCard(
                title: 'Сборщик AppBuilder Engine',
                icon: Icons.info_outline,
                child: SelectableText(
                  'Toolchain: Android Gradle Plugin ${Toolchain.androidGradlePlugin}, Gradle ${Toolchain.gradle}, '
                  'Kotlin ${Toolchain.kotlin}, compileSdk ${Toolchain.compileSdk}, minSdk ${Toolchain.minSdk}, '
                  'JDK ${Toolchain.java}, Node.js ${Toolchain.nodeMajor} LTS. Контракт v${Toolchain.contractVersion}.\n\n'
                  'Свой сервер (ПК, VPS) с Docker:\n'
                  '  docker run -d -p 8080:8080 -e ENGINE_TOKEN=<токен> -v appbuilder-data:/data '
                  'ghcr.io/<владелец>/appbuilder-engine:latest\n'
                  'или из исходников: docker compose -f engine/docker-compose.yml up -d --build\n\n'
                  'Телефон и сервер в одной Wi-Fi сети: адрес http://<IP компьютера>:8080.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _engineFields() => [
        TextField(
          controller: _engineUrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Адрес движка', hintText: 'http://192.168.1.10:8080'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _engineToken,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Токен (ENGINE_TOKEN)',
            helperText: 'Значение переменной ENGINE_TOKEN, заданной при запуске сервера',
          ),
        ),
      ];

  List<Widget> _githubFields() => [
        Row(children: [
          Expanded(child: TextField(controller: _owner, decoration: const InputDecoration(labelText: 'Владелец'))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _repo, decoration: const InputDecoration(labelText: 'Репозиторий'))),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _branch,
          decoration: const InputDecoration(
            labelText: 'Ветка (необязательно)',
            helperText: 'Пусто — ветка по умолчанию. В ней должен быть .github/workflows/inbox-build.yml',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _githubToken,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Personal access token',
            helperText: 'Fine-grained: Contents — Read and write, Actions — Read, Metadata — Read',
          ),
        ),
      ];
}
