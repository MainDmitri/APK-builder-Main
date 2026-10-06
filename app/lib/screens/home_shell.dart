import 'package:flutter/material.dart';

import '../widgets/motion.dart';
import 'builder/build_screen.dart';
import 'contract/contract_screen.dart';
import 'history/history_screen.dart';
import 'prompt/prompt_wizard_screen.dart';
import 'settings/settings_screen.dart';

/// Adaptive navigation: bottom bar on phones, rail on tablets/desktop/web.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.build_outlined, Icons.build, 'Сборка'),
    (Icons.auto_awesome_outlined, Icons.auto_awesome, 'Промпты'),
    (Icons.description_outlined, Icons.description, 'Контракт'),
    (Icons.history_outlined, Icons.history, 'История'),
    (Icons.settings_outlined, Icons.settings, 'Настройки'),
  ];

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final pages = [
      BuildScreen(onOpenSettings: () => _select(4)),
      const PromptWizardScreen(),
      const ContractScreen(),
      HistoryScreen(onOpenSettings: () => _select(4)),
      const SettingsScreen(),
    ];
    final body = IndexedStack(
      index: _index,
      children: [
        for (final (i, page) in pages.indexed) _AnimatedPage(active: i == _index, child: page),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 840) {
        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _select,
                extended: constraints.maxWidth >= 1200,
                labelType: constraints.maxWidth >= 1200 ? null : NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: GradientBadge(icon: Icons.android, size: 44),
                ),
                destinations: [
                  for (final d in _destinations)
                    NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: [
            for (final d in _destinations) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
          ],
        ),
      );
    });
  }
}

/// Tab switch animation: the page that becomes visible fades and slides in.
class _AnimatedPage extends StatelessWidget {
  const _AnimatedPage({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: active ? Offset.zero : const Offset(0, 0.025),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}
