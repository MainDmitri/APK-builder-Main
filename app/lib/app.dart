import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'services/backend/build_backend.dart';
import 'state/build_controller.dart';
import 'state/downloads_controller.dart';
import 'state/prompt_controller.dart';
import 'state/settings_controller.dart';
import 'theme/app_theme.dart';

class AppBuilderApp extends StatelessWidget {
  const AppBuilderApp({super.key, required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ProxyProvider<SettingsController, BuildBackend?>(update: (_, s, _) => s.createBackend()),
        ChangeNotifierProvider(create: (_) => DownloadsController()),
        ChangeNotifierProvider(create: (context) => BuildController(downloads: context.read<DownloadsController>())),
        ChangeNotifierProvider(create: (_) => PromptController()),
      ],
      child: Consumer<SettingsController>(
        builder: (context, s, _) => MaterialApp(
          title: 'AppBuilder',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: s.themeMode,
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const HomeShell(),
        ),
      ),
    );
  }
}
