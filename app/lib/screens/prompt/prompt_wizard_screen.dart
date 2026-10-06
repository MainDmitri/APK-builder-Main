import 'dart:convert';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/file_service.dart';
import '../../state/prompt_controller.dart';
import '../../widgets/section_card.dart';

/// Step-by-step generator of a specification ("mega-prompt") for ChatGPT,
/// Claude, DeepSeek… so that their answer builds with AppBuilder as is.
class PromptWizardScreen extends StatefulWidget {
  const PromptWizardScreen({super.key});

  @override
  State<PromptWizardScreen> createState() => _PromptWizardScreenState();
}

class _PromptWizardScreenState extends State<PromptWizardScreen> {
  int _step = 0;

  static const _typeIcons = {
    PromptAppType.utility: Icons.calculate_outlined,
    PromptAppType.webService: Icons.public,
    PromptAppType.game: Icons.sports_esports_outlined,
    PromptAppType.nativeAndroid: Icons.android,
    PromptAppType.nodeSpa: Icons.web,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PromptController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Генератор промптов для ИИ')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Stepper(
            currentStep: _step,
            onStepTapped: (s) => setState(() => _step = s),
            onStepContinue: _step < 3 ? () => setState(() => _step++) : null,
            onStepCancel: _step > 0 ? () => setState(() => _step--) : null,
            controlsBuilder: (context, details) => _step == 3
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(children: [
                      FilledButton(onPressed: details.onStepContinue, child: const Text('Далее')),
                      const SizedBox(width: 8),
                      if (_step > 0) TextButton(onPressed: details.onStepCancel, child: const Text('Назад')),
                    ]),
                  ),
            steps: [
              Step(
                title: const Text('Тип приложения'),
                subtitle: Text(c.appType.title),
                isActive: _step >= 0,
                state: _step > 0 ? StepState.complete : StepState.indexed,
                content: _typeStep(c),
              ),
              Step(
                title: const Text('Идея и идентификаторы'),
                isActive: _step >= 1,
                state: _step > 1 ? StepState.complete : StepState.indexed,
                content: _ideaStep(c),
              ),
              Step(
                title: const Text('Параметры'),
                isActive: _step >= 2,
                state: _step > 2 ? StepState.complete : StepState.indexed,
                content: _paramsStep(c),
              ),
              Step(
                title: const Text('Мега-промпт'),
                isActive: _step >= 3,
                content: _resultStep(c),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeStep(PromptController c) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in PromptAppType.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              color: c.appType == type ? scheme.primaryContainer : null,
              child: ListTile(
                leading: Icon(_typeIcons[type]),
                title: Text(type.title),
                subtitle: Text(type.examples),
                trailing: c.appType == type ? Icon(Icons.check_circle, color: scheme.primary) : null,
                onTap: () => c.update((p) => p.appType = type),
              ),
            ),
          ),
        const SizedBox(height: 8),
        ...switch (c.appType) {
          PromptAppType.game => [
              _label('Движок'),
              _segmented<GameEngine>(GameEngine.values, c.gameEngine, (v) => c.update((p) => p.gameEngine = v), (v) => v.title),
            ],
          PromptAppType.webService => [
              _label('Режим'),
              _segmented<WebServiceMode>(
                  WebServiceMode.values, c.webServiceMode, (v) => c.update((p) => p.webServiceMode = v), (v) => v.title),
            ],
          PromptAppType.nodeSpa => [
              _label('Стек'),
              _segmented<SpaFramework>(SpaFramework.values, c.spaFramework, (v) => c.update((p) => p.spaFramework = v), (v) => v.title),
            ],
          PromptAppType.nativeAndroid => [
              _label('Интерфейс'),
              _segmented<NativeUi>(NativeUi.values, c.nativeUi, (v) => c.update((p) => p.nativeUi = v), (v) => v.title),
            ],
          PromptAppType.utility => const <Widget>[],
        },
      ],
    );
  }

  Widget _ideaStep(PromptController c) {
    final needsUrl = c.appType == PromptAppType.webService;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: c.appName,
          onChanged: c.onAppNameChanged,
          decoration: InputDecoration(
            labelText: 'Название приложения',
            errorText: c.appName.text.isEmpty ? null : Validators.appName(c.appName.text),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: c.packageName,
          onChanged: (_) => c.onPackageEdited(),
          decoration: InputDecoration(
            labelText: 'Имя пакета',
            hintText: 'com.example.app',
            errorText: c.packageName.text.isEmpty ? null : Validators.packageName(c.packageName.text),
          ),
        ),
        const SizedBox(height: 12),
        if (needsUrl) ...[
          TextField(
            controller: c.remoteUrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: c.webServiceMode == WebServiceMode.remoteSite ? 'Адрес сайта' : 'Базовый URL API',
              hintText: 'https://',
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: c.description,
          minLines: 5,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: 'Что должно делать приложение',
            hintText: 'Экраны, функции, данные, поведение кнопок. Чем подробнее — тем точнее результат.',
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _paramsStep(PromptController c) {
    final perms = c.appType.isNative ? AppPermission.values : AppPermission.values.where(AppPermission.webSupported.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Ориентация экрана'),
        _segmented<ScreenOrientation>(
            ScreenOrientation.values, c.orientation, (v) => c.update((p) => p.orientation = v), (v) => v.title),
        _label('Разрешения'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in perms)
            FilterChip(label: Text(p.title), selected: c.permissions.contains(p), onSelected: (v) => c.togglePermission(p, v)),
        ]),
        _label('Офлайн-хранилище'),
        _segmented<StorageKind>(StorageKind.values, c.storage, (v) => c.update((p) => p.storage = v), (v) => v.title),
        _label('Основной цвет'),
        Wrap(spacing: 8, children: [
          for (final hex in PromptController.themeColors)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => c.update((p) => p.themeColor = hex),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                child: c.themeColor == hex ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            ),
        ]),
        _label('Язык интерфейса приложения'),
        _segmented<UiLanguage>(UiLanguage.values, c.uiLanguage, (v) => c.update((p) => p.uiLanguage = v), (v) => v.title),
        _label('Для какой нейросети'),
        _segmented<TargetAi>(TargetAi.values, c.targetAi, (v) => c.update((p) => p.targetAi = v), (v) => v.title),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: c.includeFullContract,
          onChanged: (v) => c.update((p) => p.includeFullContract = v),
          title: const Text('Приложить полный контракт AppBuilder'),
          subtitle: const Text('Длиннее, но модель увидит все правила сборщика'),
        ),
      ],
    );
  }

  Widget _resultStep(PromptController c) {
    final errors = c.errors;
    if (errors.isNotEmpty) {
      return SectionCard(
        title: 'Заполните данные',
        icon: Icons.edit_note,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MessageList(messages: errors, error: true),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => setState(() => _step = 1), child: const Text('Вернуться к описанию')),
        ]),
      );
    }
    final prompt = c.generate();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: prompt));
            showSnack(context, 'Мега-промпт скопирован — вставьте его в ${c.targetAi.title}');
          },
          icon: const Icon(Icons.content_copy),
          label: Text('Скопировать мега-промпт для ${c.targetAi.title}'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final fileName = 'prompt-${c.packageName.text.split('.').last}.md';
            final saved = await const FileService()
                .save(fileName, Uint8List.fromList(utf8.encode(prompt)), mimeType: 'text/markdown');
            if (mounted) showSnack(context, saved == null ? 'Сохранение отменено' : 'Сохранено: $saved');
          },
          icon: const Icon(Icons.save_alt),
          label: const Text('Сохранить как .md'),
        ),
        const SizedBox(height: 12),
        Text('${prompt.length} символов · ответ ИИ упакуйте в ZIP и соберите на вкладке «Сборка»',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 460),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: SelectableText(prompt, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge),
      );

  Widget _segmented<T extends Object>(List<T> values, T selected, ValueChanged<T> onChanged, String Function(T) label) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final v in values)
        ChoiceChip(label: Text(label(v)), selected: v == selected, onSelected: (_) => onChanged(v)),
    ]);
  }
}
