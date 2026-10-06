import 'package:flutter/material.dart';

import 'app.dart';
import 'state/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await SettingsController.load();
  runApp(AppBuilderApp(settings: settings));
}
