import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const NetInfoApp());

class NetInfoApp extends StatelessWidget {
  const NetInfoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Сеть',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6A1B9A),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF6A1B9A), foregroundColor: Colors.white),
      ),
      home: const NetworkScreen(),
    );
  }
}

/// Real network state: connection type, Wi-Fi parameters, gateway reachability.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> with WidgetsBindingObserver {
  final _connectivity = Connectivity();
  final _info = NetworkInfo();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  List<ConnectivityResult> _types = const [];
  String? _ip, _mask, _gateway, _ssid;
  String? _about;
  String? _gatewayCheck;
  bool _loading = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _connectivity.onConnectivityChanged.listen((_) => _refresh());
    _refresh();
    _loadAbout();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _loadAbout() async {
    final package = await PackageInfo.fromPlatform();
    final device = DeviceInfoPlugin();
    final model = Platform.isIOS
        ? '${(await device.iosInfo).utsname.machine}, iOS ${(await device.iosInfo).systemVersion}'
        : '${(await device.androidInfo).model}, Android ${(await device.androidInfo).version.release}';
    if (mounted) setState(() => _about = '${package.appName} ${package.version} · $model');
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final types = await _connectivity.checkConnectivity();
    String? ip, mask, gateway, ssid;
    if (types.contains(ConnectivityResult.wifi)) {
      ip = await _info.getWifiIP();
      mask = await _info.getWifiSubmask();
      gateway = await _info.getWifiGatewayIP();
      ssid = await _info.getWifiName();
    }
    if (!mounted) return;
    setState(() {
      _types = types;
      _ip = ip;
      _mask = mask;
      _gateway = gateway;
      _ssid = ssid;
      _loading = false;
    });
  }

  /// TCP connection to the gateway (port 80): triggers the iOS local network prompt.
  Future<void> _checkGateway() async {
    final gateway = _gateway;
    if (gateway == null) return;
    setState(() {
      _checking = true;
      _gatewayCheck = null;
    });
    String result;
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(gateway, 80, timeout: const Duration(seconds: 2));
      socket.destroy();
      result = 'Шлюз отвечает на порту 80 (${watch.elapsedMilliseconds} мс)';
    } on SocketException catch (e) {
      result = e.osError?.errorCode == 65
          ? 'Нет доступа к локальной сети: разрешите его в Настройках → Конфиденциальность → Локальная сеть'
          : 'Порт 80 шлюза недоступен: ${e.message}';
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _gatewayCheck = result;
      });
    }
  }

  String get _typeTitle {
    if (_types.isEmpty || _types.contains(ConnectivityResult.none)) return 'Нет подключения';
    return _types.map((t) => switch (t) {
          ConnectivityResult.wifi => 'Wi-Fi',
          ConnectivityResult.mobile => 'Мобильная сеть',
          ConnectivityResult.ethernet => 'Ethernet',
          ConnectivityResult.vpn => 'VPN',
          _ => t.name,
        }).join(', ');
  }

  String get _report => [
        'Подключение: $_typeTitle',
        'IP: ${_ip ?? '—'}',
        'Маска: ${_mask ?? '—'}',
        'Шлюз: ${_gateway ?? '—'}',
        'Сеть: ${_ssid ?? 'название недоступно'}',
        ?_gatewayCheck,
        ?_about,
      ].join('\n');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сеть'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Обновить', onPressed: _loading ? null : _refresh),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Сканировать QR',
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ScannerScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator.adaptive())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Row('Подключение', _typeTitle),
                  _Row('IP-адрес', _ip ?? '—'),
                  _Row('Маска подсети', _mask ?? '—'),
                  _Row('Шлюз', _gateway ?? '—'),
                  _Row('Сеть Wi-Fi', _ssid ?? 'Название недоступно (на iPhone нужно особое разрешение Apple)'),
                  if (_about != null) _Row('Устройство', _about!),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _gateway == null || _checking ? null : _checkGateway,
                    icon: const Icon(Icons.router),
                    label: Text(_checking ? 'Проверка…' : 'Проверить шлюз'),
                  ),
                  if (_gatewayCheck != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_gatewayCheck!)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox?;
                      SharePlus.instance.share(ShareParams(
                        text: _report,
                        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
                      ));
                    },
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Поделиться отчётом'),
                  ),
                  // iOS: local network and camera access are switched on in the app's settings page.
                  if (Platform.isIOS)
                    TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse('app-settings:')),
                      icon: const Icon(Icons.settings),
                      label: const Text('Открыть настройки приложения'),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.value);

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: SelectableText(value),
      );
}

/// QR / barcode scanner (mobile_scanner) with the result shown below the camera.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController();
  String? _value;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR-код')),
      body: Column(children: [
        Expanded(
          child: MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code != null && code != _value) setState(() => _value = code);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Камера недоступна: ${error.errorDetails?.message ?? error.errorCode.name}',
                    textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(_value ?? 'Наведите камеру на QR-код', textAlign: TextAlign.center),
          ),
        ),
      ]),
    );
  }
}
