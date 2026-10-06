import 'dart:convert';

import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../services/file_service.dart';
import '../../widgets/section_card.dart';

/// Built-in machine-readable contract for external AI models
/// (same text as /docs/agent-contract.md of the engine).
class ContractScreen extends StatelessWidget {
  const ContractScreen({super.key});

  static final String contract = buildAgentContract();

  Future<void> _export(BuildContext context) async {
    final saved = await const FileService()
        .save('agent-contract.md', Uint8List.fromList(utf8.encode(contract)), mimeType: 'text/markdown');
    if (context.mounted) showSnack(context, saved == null ? 'Экспорт отменён' : 'Контракт сохранён: $saved');
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: contract));
    showSnack(context, 'Контракт скопирован — вставьте его в чат с нейросетью');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Контракт для ИИ v${Toolchain.contractVersion}'),
        actions: [
          IconButton(tooltip: 'Скопировать', icon: const Icon(Icons.content_copy), onPressed: () => _copy(context)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _export(context),
        icon: const Icon(Icons.ios_share),
        label: const Text('Экспорт контракта для ИИ'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Markdown(
            data: contract,
            selectable: true,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              code: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              tableBorder: TableBorder.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
        ),
      ),
    );
  }
}
