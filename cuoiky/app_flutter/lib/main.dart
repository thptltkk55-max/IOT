import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Controller',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        fontFamily: 'Inter',
      ),
      home: const IoTControllerPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class IoTControllerPage extends StatefulWidget {
  const IoTControllerPage({super.key});

  @override
  State<IoTControllerPage> createState() => _IoTControllerPageState();
}

class _IoTControllerPageState extends State<IoTControllerPage> {
  // MQTT connection states
  bool _brokerConnected = false;
  bool _deviceOnline = false;
  String _lightState = 'off';
  String _fanState = 'off';
  bool _autoFan = true;

  double _temperature = 0;
  double _humidity = 0;
  String _rssi = '--';
  String _firmware = '--';
  String _lastUpdate = '--';

  @override
  void initState() {
    super.initState();
    _initializeMQTT();
  }

  void _initializeMQTT() {
    html.document.head!.append(html.ScriptElement()
      ..src = 'https://unpkg.com/mqtt/dist/mqtt.min.js'
      ..onLoad.listen((_) => _connectMQTT()));
  }

  void _connectMQTT() {
    const broker = 'wss://broker.hivemq.com:8884/mqtt';
    const topicNamespace = 'demo/room1';

    js.context.callMethod('eval', ['''
      window.flutterMqttClient = mqtt.connect('$broker', {
        clientId: 'flutter_web_' + Math.random().toString(16).substr(2, 8)
      });
      window.flutterMqttClient.on('connect', function() {
        console.log('Flutter MQTT connected');
        window.dispatchEvent(new CustomEvent('mqtt_connected'));
        window.flutterMqttClient.subscribe('$topicNamespace/device/state');
        window.flutterMqttClient.subscribe('$topicNamespace/sys/online');
        window.flutterMqttClient.subscribe('$topicNamespace/sensor/data');
      });
      window.flutterMqttClient.on('message', function(topic, message) {
        const payload = message.toString();
        window.dispatchEvent(new CustomEvent('mqtt_message', {
          detail: { topic: topic, payload: payload }
        }));
      });
      window.flutterMqttClient.on('error', function(error) {
        console.error('MQTT Error:', error);
        window.dispatchEvent(new CustomEvent('mqtt_error'));
      });
      window.sendMqttCommand = function(device, action) {
        const topic = '$topicNamespace/device/cmd';
        const command = {};
        command[device] = action;
        window.flutterMqttClient.publish(topic, JSON.stringify(command));
      };
    ''']);

    html.window.addEventListener('mqtt_connected', (event) {
      if (!mounted) return;
      setState(() => _brokerConnected = true);
    });

    html.window.addEventListener('mqtt_message', (event) {
      if (!mounted) return;
      final detail = (event as html.CustomEvent).detail;
      final topic = detail['topic'];
      final payload = detail['payload'];
      _handleMqttMessage(topic, payload);
    });

    html.window.addEventListener('mqtt_error', (event) {
      if (!mounted) return;
      setState(() {
        _brokerConnected = false;
        _deviceOnline = false;
      });
    });
  }

  void _handleMqttMessage(String topic, String payload) {
    try {
      final data = jsonDecode(payload);
      if (topic.endsWith('/device/state')) {
        setState(() {
          _lightState = data['light'] ?? 'off';
          _fanState = data['fan'] ?? 'off';
          _autoFan = data['autoFan'] ?? true;
          _rssi = '${data['rssi'] ?? 0} dBm';
          _firmware = data['fw'] ?? '--';
          _lastUpdate = DateTime.now().toString().substring(11, 19);
        });
      } else if (topic.endsWith('/sys/online')) {
        setState(() => _deviceOnline = data['online'] ?? false);
      } else if (topic.endsWith('/sensor/data')) {
        setState(() {
          _temperature = (data['temp'] ?? 0).toDouble();
          _humidity = (data['humidity'] ?? 0).toDouble();
        });
      }
    } catch (_) {}
  }

  void _toggleDevice(String device) {
    if (!_brokerConnected || !_deviceOnline) return;
    js.context.callMethod('sendMqttCommand', [device, 'toggle']);
  }

  void _toggleAutoFan(bool value) {
    if (!_brokerConnected || !_deviceOnline) return;
    js.context.callMethod('sendMqttCommand', ['autoFan', !(_autoFan)]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('🏠 IoT Controller Web'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade400.withOpacity(0.8), Colors.purple.shade400.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.purple.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Status Row
                        Row(
                          children: [
                            Expanded(
                              child: _StatusCard(
                                title: 'MQTT Broker',
                                status: _brokerConnected ? 'Connected' : 'Connecting...',
                                icon: _brokerConnected ? Icons.wifi : Icons.wifi_off,
                                gradient: _brokerConnected
                                    ? [Colors.green.shade400, Colors.green.shade600]
                                    : [Colors.orange.shade400, Colors.orange.shade600],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatusCard(
                                title: 'ESP32 Device',
                                status: _deviceOnline ? 'Online' : 'Offline',
                                icon: _deviceOnline ? Icons.developer_board : Icons.developer_board_off,
                                gradient: _deviceOnline
                                    ? [Colors.blue.shade400, Colors.blue.shade600]
                                    : [Colors.grey.shade400, Colors.grey.shade600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Controls
                        _ControlCard(
                          title: '💡 Smart Light',
                          icon: Icons.lightbulb_rounded,
                          value: _lightState == 'on',
                          onChanged: (_brokerConnected && _deviceOnline) ? (v) => _toggleDevice('light') : null,
                          subtitle: 'Status: ${_lightState.toUpperCase()}',
                          activeGradient: [Colors.orange.shade400, Colors.orange.shade600],
                        ),
                        const SizedBox(height: 16),
                        _ControlCard(
                          title: '🌀 Smart Fan',
                          icon: Icons.air_rounded,
                          value: _fanState == 'on',
                          onChanged: (_brokerConnected && _deviceOnline) ? (v) => _toggleDevice('fan') : null,
                          subtitle: 'Status: ${_fanState.toUpperCase()}',
                          activeGradient: [Colors.cyan.shade400, Colors.cyan.shade600],
                        ),
                        const SizedBox(height: 16),
                        _ControlCard(
                          title: '⚡ Auto Fan',
                          icon: Icons.settings_remote_rounded,
                          value: _autoFan,
                          onChanged: (_brokerConnected && _deviceOnline) ? _toggleAutoFan : null,
                          subtitle: 'Auto Mode: ${_autoFan ? "ON" : "OFF"}',
                          activeGradient: [Colors.purple.shade400, Colors.purple.shade600],
                        ),
                        const SizedBox(height: 24),

                        // Info Card
                        Card(
                          elevation: 8,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [Colors.purple.shade50, Colors.blue.shade50],
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info_rounded, color: Colors.purple.shade700),
                                    const SizedBox(width: 8),
                                    Text('Device Information',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold, color: Colors.purple.shade800, fontSize: 16)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _InfoRow('📡 WiFi Signal', _rssi),
                                _InfoRow('💿 Firmware', _firmware),
                                _InfoRow('⏰ Last Update', _lastUpdate),
                                _InfoRow('🌡 Temperature', '${_temperature.toStringAsFixed(1)} °C'),
                                _InfoRow('💧 Humidity', '${_humidity.toStringAsFixed(1)} %'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _InfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: Colors.purple.shade700)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(value, style: TextStyle(color: Colors.purple.shade800, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// Status Card Widget
class _StatusCard extends StatelessWidget {
  final String title;
  final String status;
  final IconData icon;
  final List<Color> gradient;

  const _StatusCard({
    required this.title,
    required this.status,
    required this.icon,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(colors: gradient),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// Control Card Widget
class _ControlCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String subtitle;
  final List<Color> activeGradient;

  const _ControlCard({
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
    required this.subtitle,
    required this.activeGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: value ? 8 : 4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: value
              ? LinearGradient(colors: activeGradient)
              : LinearGradient(colors: [Colors.grey.shade100, Colors.grey.shade200]),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: value ? Colors.white : Colors.grey.shade600, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: value ? Colors.white : Colors.grey.shade800)),
                  Text(subtitle, style: TextStyle(color: value ? Colors.white70 : Colors.grey.shade600)),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged, activeColor: Colors.white),
          ],
        ),
      ),
    );
  }
}
