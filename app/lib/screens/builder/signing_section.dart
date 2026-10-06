import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/backend/build_backend.dart';
import '../../state/build_controller.dart';
import '../../widgets/section_card.dart';

/// Debug key / production keystore (engine) / repository secrets (GitHub).
class SigningSection extends StatelessWidget {
  const SigningSection({super.key, required this.backend});

  final BuildBackend? backend;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BuildController>();
    final upload = backend?.supportsKeystoreUpload ?? true;
    final modes = upload ? const [SigningMode.debug, SigningMode.keystore] : const [SigningMode.debug, SigningMode.repoSecrets];
    if (!modes.contains(c.signing)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.setSigning(SigningMode.debug));
    }
    final selected = modes.contains(c.signing) ? c.signing : SigningMode.debug;

    return SectionCard(
      title: 'Подпись APK',
      icon: Icons.verified_user_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<SigningMode>(
            segments: [for (final m in modes) ButtonSegment(value: m, label: Text(m.title))],
            selected: {selected},
            onSelectionChanged: (s) => c.setSigning(s.first),
          ),
          const SizedBox(height: 12),
          switch (selected) {
            SigningMode.debug => const Text(
                'Постоянный debug-ключ сборщика (androiddebugkey). Подходит для установки и тестирования; '
                'для Google Play нужен собственный ключ. zipalign + схемы v1, v2, v3.'),
            SigningMode.repoSecrets => const Text(
                'Ключ берётся из секретов репозитория (Settings → Secrets and variables → Actions): '
                'KEYSTORE_BASE64 (base64 -w0 release.jks), KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD.'),
            SigningMode.keystore => _KeystoreForm(controller: c, backend: backend),
          },
        ],
      ),
    );
  }
}

class _KeystoreForm extends StatefulWidget {
  const _KeystoreForm({required this.controller, required this.backend});

  final BuildController controller;
  final BuildBackend? backend;

  @override
  State<_KeystoreForm> createState() => _KeystoreFormState();
}

class _KeystoreFormState extends State<_KeystoreForm> {
  bool _showPasswords = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final check = c.keystoreCheck;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: c.pickKeystore,
          icon: const Icon(Icons.key),
          label: Text(c.keystore == null ? 'Выбрать .jks / .keystore / .p12' : c.keystore!.name),
        ),
        if (c.keystoreFormatError != null) ...[
          const SizedBox(height: 8),
          MessageList(messages: [c.keystoreFormatError!], error: true),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: c.storePassword,
          obscureText: !_showPasswords,
          onChanged: (_) => c.touch(),
          decoration: InputDecoration(
            labelText: 'Пароль хранилища (storePassword)',
            errorText: c.storePassword.text.isEmpty ? null : Validators.keystorePassword(c.storePassword.text),
            suffixIcon: IconButton(
              icon: Icon(_showPasswords ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showPasswords = !_showPasswords),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: c.keyAlias,
          onChanged: (_) => c.touch(),
          decoration: const InputDecoration(labelText: 'Alias ключа'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: c.keyPassword,
          obscureText: !_showPasswords,
          onChanged: (_) => c.touch(),
          decoration: const InputDecoration(
            labelText: 'Пароль ключа (keyPassword)',
            helperText: 'Пусто — используется пароль хранилища (обычно для PKCS12)',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: widget.backend == null || c.keystore == null || c.checkingKeystore || c.keystoreFormatError != null
              ? null
              : () => c.validateKeystore(widget.backend!),
          icon: c.checkingKeystore
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.fact_check_outlined),
          label: const Text('Проверить пароли и alias (keytool)'),
        ),
        if (check != null) ...[
          const SizedBox(height: 12),
          if (check.valid)
            Card(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  'Ключ подходит ✔\n'
                  'Владелец: ${check.owner ?? '-'}\n'
                  'Действителен до: ${check.validUntil ?? '-'}\n'
                  'SHA-256: ${check.sha256 ?? '-'}\n'
                  'Alias в хранилище: ${check.aliases.join(', ')}',
                ),
              ),
            )
          else
            MessageList(messages: [check.error ?? 'Keystore не прошёл проверку'], error: true),
        ],
        const SizedBox(height: 8),
        const Text('Ключ и пароли передаются только на ваш сервер сборки, используются для одной '
            'сборки и сразу удаляются. Приложение их не сохраняет.'),
      ],
    );
  }
}
