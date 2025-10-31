import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:provider/provider.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MqttController(),
      child: MaterialApp(
        title: 'IoT Controller',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          useMaterial3: true,
          fontFamily: 'Inter',
        ),
        home: const IoTControllerPage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class IoTControllerPage extends StatefulWidget {
  const IoTControllerPage({super.key});
  @override
  State<IoTControllerPage> createState() => _IoTControllerPageState();
}

class _IoTControllerPageState extends State<IoTControllerPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MqttController>().connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏠 IoT Device Controller'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400, Colors.purple.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Consumer<MqttController>(
        builder: (context, ctrl, child) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Status Cards
                  Row(
                    children: [
                      Expanded(
                        child: _StatusCard(
                          title: 'MQTT Broker',
                          status: ctrl.brokerConnected ? 'Connected' : 'Disconnected',
                          icon: ctrl.brokerConnected ? Icons.wifi : Icons.wifi_off,
                          gradient: ctrl.brokerConnected
                              ? [Colors.green.shade400, Colors.green.shade600]
                              : [Colors.red.shade400, Colors.red.shade600],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatusCard(
                          title: 'ESP32 Device',
                          status: ctrl.deviceOnline ? 'Online' : 'Offline',
                          icon: ctrl.deviceOnline ? Icons.developer_board : Icons.developer_board_off,
                          gradient: ctrl.deviceOnline
                              ? [Colors.blue.shade400, Colors.blue.shade600]
                              : [Colors.grey.shade400, Colors.grey.shade600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Control Cards
                  _ControlCard(
                    title: '💡 Smart Light',
                    icon: Icons.lightbulb_rounded,
                    value: ctrl.lightState == 'on',
                    onChanged: ctrl.brokerConnected && ctrl.deviceOnline
                        ? (v) => ctrl.toggleDevice('light')
                        : null,
                    subtitle: 'Status: ${ctrl.lightState.toUpperCase()}',
                    activeGradient: [Colors.orange.shade400, Colors.orange.shade600],
                  ),
                  const SizedBox(height: 16),
                  _ControlCard(
                    title: '🌀 Smart Fan',
                    icon: Icons.air_rounded,
                    value: ctrl.fanState == 'on',
                    onChanged: ctrl.brokerConnected && ctrl.deviceOnline
                        ? (v) => ctrl.toggleDevice('fan')
                        : null,
                    subtitle: 'Status: ${ctrl.fanState.toUpperCase()}',
                    activeGradient: [Colors.cyan.shade400, Colors.cyan.shade600],
                  ),
                  const SizedBox(height: 16),
                  _ControlCard(
                    title: '⚡ Auto Fan',
                    icon: Icons.settings_remote_rounded,
                    value: ctrl.autoFan,
                    onChanged: ctrl.brokerConnected && ctrl.deviceOnline
                        ? (v) => ctrl.toggleDevice('autoFan')
                        : null,
                    subtitle: 'Auto Mode: ${ctrl.autoFan ? "ON" : "OFF"}',
                    activeGradient: [Colors.purple.shade400, Colors.purple.shade600],
                  ),
                  const SizedBox(height: 16),

                  // Temperature & Humidity
                  Row(
                    children: [
                      Expanded(child: TemperatureCard(temperature: ctrl.temperature)),
                      const SizedBox(width: 12),
                      Expanded(child: HumidityCard(humidity: ctrl.humidity)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Device Info
                  Card(
                    elevation: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: [Colors.purple.shade50, Colors.blue.shade50],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.info_rounded, color: Colors.purple.shade700, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Text('Device Information',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _InfoRow('📡 WiFi Signal', '${ctrl.rssi} dBm'),
                          _InfoRow('💿 Firmware', ctrl.firmware),
                          _InfoRow('⏰ Last Update', ctrl.lastUpdate),
                        ],
                      ),
                    ),
                  ),

                  // Reconnect Button
                  if (!ctrl.brokerConnected)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: ElevatedButton.icon(
                        onPressed: ctrl.isConnecting ? null : ctrl.connect,
                        icon: ctrl.isConnecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh_rounded, color: Colors.white),
                        label: Text(ctrl.isConnecting ? 'Connecting...' : 'Reconnect to Broker'),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _InfoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.purple.shade700)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration:
                  BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(8)),
              child: Text(value, style: TextStyle(color: Colors.purple.shade800, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
}

// ================= Status Card =================
class _StatusCard extends StatelessWidget {
  final String title, status;
  final IconData icon;
  final List<Color> gradient;
  const _StatusCard({required this.title, required this.status, required this.icon, required this.gradient});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Container(
        height: 90,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: gradient)),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text(status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= Control Card =================
class _ControlCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final List<Color> activeGradient;

  const _ControlCard(
      {required this.title,
      required this.icon,
      required this.value,
      required this.onChanged,
      required this.subtitle,
      required this.activeGradient});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: value ? 8 : 4,
      child: Container(
        height: 75,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: value ? LinearGradient(colors: activeGradient) : LinearGradient(colors: [Colors.grey.shade200, Colors.grey.shade300])),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, color: value ? Colors.white : Colors.grey.shade600, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: value ? Colors.white : Colors.grey.shade800)),
                  Text(subtitle, style: TextStyle(fontSize: 14, color: value ? Colors.white70 : Colors.grey.shade600)),
                ],
              ),
            ),
            if (onChanged != null) Switch(value: value, onChanged: onChanged, activeColor: Colors.white),
          ],
        ),
      ),
    );
  }
}

// ================= Temp & Humidity =================
class TemperatureCard extends StatelessWidget {
  final double temperature;
  const TemperatureCard({super.key, required this.temperature});

  @override
  Widget build(BuildContext context) {
    final grad = _gradient(temperature);
    return Card(
      elevation: 4,
      child: Container(
        height: 75,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: grad)),
        child: Center(
            child: Text("🌡️ ${temperature.toStringAsFixed(1)} °C",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
      ),
    );
  }

  List<Color> _gradient(double temp) {
    if (temp < 20) return [Colors.blue.shade400, Colors.blue.shade600];
    if (temp < 25) return [Colors.green.shade400, Colors.green.shade600];
    if (temp < 30) return [Colors.orange.shade400, Colors.orange.shade600];
    return [Colors.red.shade400, Colors.red.shade600];
  }
}

class HumidityCard extends StatelessWidget {
  final double humidity;
  const HumidityCard({super.key, required this.humidity});

  @override
  Widget build(BuildContext context) {
    final grad = _gradient(humidity);
    return Card(
      elevation: 4,
      child: Container(
        height: 75,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: grad)),
        child: Center(
            child: Text("💧 ${humidity.toStringAsFixed(1)} %",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
      ),
    );
  }

  List<Color> _gradient(double hum) {
    if (hum < 30) return [Colors.yellow.shade400, Colors.yellow.shade600];
    if (hum < 60) return [Colors.green.shade400, Colors.green.shade600];
    return [Colors.blue.shade400, Colors.blue.shade600];
  }
}

// ================= MQTT Controller =================
class MqttController extends ChangeNotifier {
  static const String mqttHost = 'broker.hivemq.com';
  static const int mqttPort = 1883;
  static const String topicNamespace = 'demo/room1';

  late MqttServerClient _client;

  bool _brokerConnected = false, _deviceOnline = false, _isConnecting = false;

  String _lightState = 'off';
  String _fanState = 'off';
  bool _autoFan = true;

  String _rssi = '--';
  String _firmware = '--';
  String _lastUpdate = '--';
  double _temperature = 0;
  double _humidity = 0;

  late final String _deviceCmdTopic;
  late final String _deviceStateTopic;
  late final String _sysOnlineTopic;
  late final String _topicSensorData;

  // ====== Getters ======
  bool get brokerConnected => _brokerConnected;
  bool get deviceOnline => _deviceOnline;
  bool get isConnecting => _isConnecting;
  String get lightState => _lightState;
  String get fanState => _fanState;
  bool get autoFan => _autoFan;
  String get rssi => _rssi;
  String get firmware => _firmware;
  String get lastUpdate => _lastUpdate;
  double get temperature => _temperature;
  double get humidity => _humidity;

  MqttController() {
    _deviceCmdTopic = '$topicNamespace/device/cmd';
    _deviceStateTopic = '$topicNamespace/device/state';
    _sysOnlineTopic = '$topicNamespace/sys/online';
    _topicSensorData = '$topicNamespace/sensor/data';
    _initClient();
  }

  void _initClient() {
    final clientId = 'flutter_client_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient.withPort(mqttHost, clientId, mqttPort);
    _client.logging(on: true);
    _client.keepAlivePeriod = 30;
    _client.autoReconnect = true;

    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;
    _client.onSubscribed = _onSubscribed;
    _client.onSubscribeFail = _onSubscribeFail;
    _client.pongCallback = _pong;
  }

  Future<void> connect() async {
    if (_isConnecting) return;
    _isConnecting = true;
    notifyListeners();

    try {
      final connMsg = MqttConnectMessage()
          .withClientIdentifier(_client.clientIdentifier)
          .withWillTopic('$topicNamespace/app/online')
          .withWillMessage('{"online":false}')
          .withWillRetain()
          .startClean()
          .withWillQos(MqttQos.atLeastOnce);
      _client.connectionMessage = connMsg;
      await _client.connect();
    } catch (_) {
      _resetConnection();
    }
  }

  void _onConnected() {
    _brokerConnected = true;
    _isConnecting = false;
    [_deviceStateTopic, _sysOnlineTopic, _topicSensorData].forEach((t) => _client.subscribe(t, MqttQos.atLeastOnce));
    _client.updates!.listen(_onMessage);
    notifyListeners();
  }

  void _onDisconnected() => _resetConnection();

  void _resetConnection() {
    _brokerConnected = false;
    _deviceOnline = false;
    _isConnecting = false;
    notifyListeners();
  }

  void _onSubscribed(String topic) => print('Subscribed: $topic');
  void _onSubscribeFail(String topic) => print('Subscribe fail: $topic');
  void _pong() => print('Ping OK');

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final msg in messages) {
      final payload = MqttPublishPayload.bytesToStringAsString((msg.payload as MqttPublishMessage).payload.message);
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        if (msg.topic == _deviceStateTopic) _handleDeviceState(data);
        if (msg.topic == _sysOnlineTopic) _handleOnlineStatus(data);
        if (msg.topic == _topicSensorData) _handleSensorData(data);
        _updateLastUpdate();
        notifyListeners();
      } catch (_) {}
    }
  }

  void _handleDeviceState(Map<String, dynamic> d) {
    _lightState = d['light'] ?? _lightState;
    _fanState = d['fan'] ?? _fanState;
    _autoFan = d['autoFan'] ?? _autoFan;
    _rssi = d['rssi']?.toString() ?? _rssi;
    _firmware = d['fw'] ?? _firmware;
  }

  void _handleOnlineStatus(Map<String, dynamic> d) => _deviceOnline = d['online'] ?? _deviceOnline;

  void _handleSensorData(Map<String, dynamic> d) {
    _temperature = (d['temp'] ?? _temperature).toDouble();
    _humidity = (d['humidity'] ?? _humidity).toDouble();
  }

  void _updateLastUpdate() {
    final now = DateTime.now();
    _lastUpdate =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  void toggleDevice(String device) {
    if (!_brokerConnected) return;
    final builder = MqttClientPayloadBuilder();
    if (device == 'autoFan') {
      builder.addString(jsonEncode({device: !_autoFan}));
    } else {
      builder.addString(jsonEncode({device: 'toggle'}));
    }
    _client.publishMessage(_deviceCmdTopic, MqttQos.atLeastOnce, builder.payload!);
  }

  @override
  void dispose() {
    _client.disconnect();
    super.dispose();
  }
}
