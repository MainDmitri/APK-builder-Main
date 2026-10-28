import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const CounterApp());

class CounterApp extends StatelessWidget {
  const CounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Счётчик',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFFEF6C00), useMaterial3: true),
      home: const CounterScreen(),
    );
  }
}

/// Counter that survives restarts (shared_preferences).
class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  static const _key = 'counter';
  final _prefs = SharedPreferencesAsync();
  int? _count;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await _prefs.getInt(_key) ?? 0;
    if (mounted) setState(() => _count = saved);
  }

  Future<void> _change(int delta) async {
    final next = (_count ?? 0) + delta;
    setState(() => _count = next);
    await _prefs.setInt(_key, next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Счётчик'),
        backgroundColor: const Color(0xFFEF6C00),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _count == null
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Нажато раз:', style: theme.textTheme.titleMedium),
                  Text('$_count', style: theme.textTheme.displayLarge),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.tonal(onPressed: () => _change(-1), child: const Icon(Icons.remove)),
                      const SizedBox(width: 16),
                      FilledButton(onPressed: () => _change(1), child: const Icon(Icons.add)),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
