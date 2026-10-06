import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/backend/build_backend.dart';
import '../services/backend/engine_backend.dart';
import '../services/backend/github_backend.dart';

/// Persistent app settings (shared_preferences).
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) {
    _mode = BackendMode.values.firstWhere((m) => m.name == _prefs.getString(_kMode), orElse: () => BackendMode.engine);
    _engineUrl = _prefs.getString(_kEngineUrl) ?? '';
    _engineToken = _prefs.getString(_kEngineToken) ?? '';
    _githubOwner = _prefs.getString(_kGithubOwner) ?? '';
    _githubRepo = _prefs.getString(_kGithubRepo) ?? '';
    _githubBranch = _prefs.getString(_kGithubBranch) ?? '';
    _githubToken = _prefs.getString(_kGithubToken) ?? '';
    _themeMode = ThemeMode.values.firstWhere((m) => m.name == _prefs.getString(_kTheme), orElse: () => ThemeMode.system);
  }

  static Future<SettingsController> load() async => SettingsController(await SharedPreferences.getInstance());

  static const _kMode = 'backend.mode';
  static const _kEngineUrl = 'engine.url';
  static const _kEngineToken = 'engine.token';
  static const _kGithubOwner = 'github.owner';
  static const _kGithubRepo = 'github.repo';
  static const _kGithubBranch = 'github.branch';
  static const _kGithubToken = 'github.token';
  static const _kTheme = 'ui.theme';

  final SharedPreferences _prefs;
  late BackendMode _mode;
  late String _engineUrl;
  late String _engineToken;
  late String _githubOwner;
  late String _githubRepo;
  late String _githubBranch;
  late String _githubToken;
  late ThemeMode _themeMode;

  BackendMode get mode => _mode;
  String get engineUrl => _engineUrl;
  String get engineToken => _engineToken;
  String get githubOwner => _githubOwner;
  String get githubRepo => _githubRepo;
  String get githubBranch => _githubBranch;
  String get githubToken => _githubToken;
  ThemeMode get themeMode => _themeMode;

  bool get isConfigured => switch (_mode) {
        BackendMode.engine => Uri.tryParse(_engineUrl)?.hasScheme ?? false,
        BackendMode.github => _githubOwner.isNotEmpty && _githubRepo.isNotEmpty && _githubToken.isNotEmpty,
      };

  /// A new backend client for the current settings (null if not configured).
  BuildBackend? createBackend() {
    if (!isConfigured) return null;
    return switch (_mode) {
      BackendMode.engine => EngineBackend(baseUrl: _engineUrl, token: _engineToken),
      BackendMode.github => GitHubBackend(
          owner: _githubOwner,
          repo: _githubRepo,
          token: _githubToken,
          branch: _githubBranch.isEmpty ? null : _githubBranch,
        ),
    };
  }

  Future<void> setMode(BackendMode mode) async {
    _mode = mode;
    await _prefs.setString(_kMode, mode.name);
    notifyListeners();
  }

  Future<void> saveEngine({required String url, required String token}) async {
    _engineUrl = url.trim();
    _engineToken = token.trim();
    await _prefs.setString(_kEngineUrl, _engineUrl);
    await _prefs.setString(_kEngineToken, _engineToken);
    notifyListeners();
  }

  Future<void> saveGithub({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    _githubOwner = owner.trim();
    _githubRepo = repo.trim();
    _githubBranch = branch.trim();
    _githubToken = token.trim();
    await _prefs.setString(_kGithubOwner, _githubOwner);
    await _prefs.setString(_kGithubRepo, _githubRepo);
    await _prefs.setString(_kGithubBranch, _githubBranch);
    await _prefs.setString(_kGithubToken, _githubToken);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setString(_kTheme, mode.name);
    notifyListeners();
  }
}
