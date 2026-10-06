/// Versions of the Android/Node toolchain installed in the AppBuilder Engine.
///
/// Single source of truth: the engine generates Gradle projects from these
/// values, and the agent contract / prompt generator quote them so that
/// external AI models produce code that compiles against exactly this setup.
abstract final class Toolchain {
  static const String contractVersion = '1.0';

  static const String androidGradlePlugin = '9.1.0';
  static const String kotlin = '2.4.0';
  static const String gradle = '9.3.1';
  static const int compileSdk = 36;
  static const int targetSdk = 36;
  static const int minSdk = 24;
  static const String buildTools = '36.0.0';
  static const int java = 17;
  static const int nodeMajor = 24;

  /// Host the web shell serves bundled web assets from.
  static const String webAssetHost = 'appassets.androidplatform.net';
  static const String webAssetOrigin = 'https://$webAssetHost';

  static const String webkitDependency = 'androidx.webkit:webkit:1.12.1';
  static const String coreDependency = 'androidx.core:core:1.15.0';

  /// Always available to native projects built in "sources" mode.
  static const List<String> nativeBaseDependencies = [
    'androidx.core:core-ktx:1.15.0',
    'androidx.appcompat:appcompat:1.7.0',
    'com.google.android.material:material:1.12.0',
    'androidx.constraintlayout:constraintlayout:2.2.0',
    'androidx.activity:activity-ktx:1.9.3',
    'androidx.lifecycle:lifecycle-runtime-ktx:2.8.7',
    'androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7',
    'androidx.recyclerview:recyclerview:1.3.2',
    'org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2',
  ];

  static const String composeBom = 'androidx.compose:compose-bom:2024.12.01';

  /// Added when the sources use Jetpack Compose (versions come from the BOM
  /// unless pinned explicitly).
  static const List<String> composeDependencies = [
    'androidx.compose.ui:ui',
    'androidx.compose.ui:ui-graphics',
    'androidx.compose.ui:ui-tooling-preview',
    'androidx.compose.foundation:foundation',
    'androidx.compose.material3:material3',
    'androidx.compose.material:material-icons-core',
    'androidx.activity:activity-compose:1.9.3',
    'androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7',
    'androidx.lifecycle:lifecycle-runtime-compose:2.8.7',
  ];

  /// npm versions verified to build with the engine (used in generated
  /// prompts so external AIs pin compatible releases).
  static const Map<String, String> webStack = {
    'vite': '^8.3.2',
    'react': '^19.3.0',
    'react-dom': '^19.3.0',
    '@vitejs/plugin-react': '^6.1.2',
    'react-router-dom': '^7.18.4',
    'vue': '^3.5.43',
    '@vitejs/plugin-vue': '^6.0.9',
    'vue-router': '^4.6.4',
    'tailwindcss': '^4.3.3',
    '@tailwindcss/vite': '^4.3.3',
    'phaser': '^3.90.0',
    'three': '^0.186.1',
  };
}
