import 'package:appbuilder/app.dart';
import 'package:appbuilder/state/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pumpApp(WidgetTester tester, {Map<String, Object> prefs = const {}, double height = 2400}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final settings = await SettingsController.load();
  tester.view.physicalSize = Size(1080, height);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppBuilderApp(settings: settings));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('build screen asks to configure the backend', (tester) async {
    await pumpApp(tester);
    expect(find.text('Сборка APK'), findsOneWidget);
    expect(find.text('Сборщик не настроен'), findsOneWidget);
    expect(find.text('Выбрать ZIP'), findsOneWidget);
  });

  testWidgets('configured engine is shown on the build screen', (tester) async {
    await pumpApp(tester, prefs: {'backend.mode': 'engine', 'engine.url': 'http://10.0.0.5:8080'});
    expect(find.text('http://10.0.0.5:8080'), findsOneWidget);
    expect(find.text('Сборщик не настроен'), findsNothing);
  });

  testWidgets('prompt wizard generates a mega-prompt', (tester) async {
    // A tall phone screen keeps every wizard step on screen.
    await pumpApp(tester, height: 7000);
    await tester.tap(find.text('Промпты'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Нативный Android-проект'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Далее').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Название приложения'), 'Shop List');
    await tester.enterText(find.widgetWithText(TextField, 'Что должно делать приложение'),
        'Список покупок с категориями и отметкой купленного.');
    await tester.pumpAndSettle();
    expect(find.text('com.example.shoplist'), findsOneWidget);

    await tester.tap(find.text('Мега-промпт'));
    await tester.pumpAndSettle();
    expect(find.text('Скопировать мега-промпт для ChatGPT'), findsOneWidget);
    expect(find.textContaining('app/src/main/java/com/example/shoplist/MainActivity.kt'), findsWidgets);
  });

  testWidgets('contract screen shows the agent contract', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Контракт'));
    await tester.pumpAndSettle();
    expect(find.text('Экспорт контракта для ИИ'), findsOneWidget);
    expect(find.textContaining('AppBuilder Engine — AI Agent Contract', findRichText: true), findsWidgets);
  });

  testWidgets('settings switch to GitHub mode', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GitHub Actions'));
    await tester.pumpAndSettle();
    expect(find.text('Personal access token'), findsOneWidget);
  });
}
