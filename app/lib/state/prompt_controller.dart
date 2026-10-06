import 'package:appbuilder_core/appbuilder_core.dart';
import 'package:flutter/widgets.dart';

/// State of the AI prompt wizard.
class PromptController extends ChangeNotifier {
  PromptController() {
    for (final c in [appName, packageName, description, remoteUrl]) {
      c.addListener(notifyListeners);
    }
  }

  static const generator = PromptGenerator();

  final appName = TextEditingController();
  final packageName = TextEditingController();
  final description = TextEditingController();
  final remoteUrl = TextEditingController();

  PromptAppType appType = PromptAppType.utility;
  GameEngine gameEngine = GameEngine.canvas;
  WebServiceMode webServiceMode = WebServiceMode.apiClient;
  SpaFramework spaFramework = SpaFramework.react;
  NativeUi nativeUi = NativeUi.compose;
  ScreenOrientation orientation = ScreenOrientation.portrait;
  Set<AppPermission> permissions = {AppPermission.internet};
  StorageKind storage = StorageKind.keyValue;
  String themeColor = '#1565C0';
  UiLanguage uiLanguage = UiLanguage.ru;
  TargetAi targetAi = TargetAi.chatgpt;
  bool includeFullContract = false;

  /// Package name typed by the user (disables auto-suggestion).
  bool _packageEdited = false;

  static const themeColors = ['#1565C0', '#2E7D32', '#6A1B9A', '#C62828', '#EF6C00', '#00838F', '#37474F', '#AD1457'];

  PromptConfig get config => PromptConfig(
        appType: appType,
        appName: appName.text.trim(),
        packageName: packageName.text.trim(),
        orientation: orientation,
        permissions: permissions,
        storage: storage,
        description: description.text.trim(),
        themeColor: themeColor,
        uiLanguage: uiLanguage,
        targetAi: targetAi,
        gameEngine: gameEngine,
        webServiceMode: webServiceMode,
        remoteUrl: remoteUrl.text.trim(),
        spaFramework: spaFramework,
        nativeUi: nativeUi,
        includeFullContract: includeFullContract,
      );

  List<String> get errors => generator.validate(config);

  String generate() => generator.generate(config);

  /// Suggests `com.example.<name>` until the user edits the package manually.
  void onAppNameChanged(String name) {
    if (_packageEdited) return;
    packageName.text = 'com.example.${Validators.packageSegmentFrom(name)}';
  }

  void onPackageEdited() => _packageEdited = true;

  void update(void Function(PromptController c) change) {
    change(this);
    if (!appType.isNative) permissions = permissions.where(AppPermission.webSupported.contains).toSet();
    notifyListeners();
  }

  void togglePermission(AppPermission permission, bool enabled) {
    permissions = {...permissions};
    enabled ? permissions.add(permission) : permissions.remove(permission);
    notifyListeners();
  }

  @override
  void dispose() {
    for (final c in [appName, packageName, description, remoteUrl]) {
      c.dispose();
    }
    super.dispose();
  }
}
