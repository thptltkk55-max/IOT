// ==================== ESP32-S3 IoT (GPIO2 + DHT22 + L298N Fan + MQTT + InfluxDB) ====================
#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <DHT.h>

// ========= USER CONFIG =========
const char* WIFI_SSID     = "Hoi Coffee 1";
const char* WIFI_PASSWORD = "12356789";

static const bool USE_LOCAL_BROKER = false;
const char* MQTT_HOST_PUBLIC = "broker.hivemq.com";
const char* MQTT_HOST_LOCAL  = "192.168.1.10";
const int   MQTT_PORT        = 1883;

const char* TOPIC_NS = "demo/room1";  
const char* DEVICE_ID = "esp32s3_luong_001";
const char* FIRMWARE_VERSION = "luongfw-1.3.1";

// ========= INFLUXDB CONFIG =========
const char* INFLUXDB_URL = "http://192.168.1.100:8086/api/v2/write?org=myorg&bucket=mybucket&precision=s";
const char* INFLUXDB_TOKEN = "your-influxdb-token";

// ========= PIN MAP =========
#define LED_PIN 2
#define DHT_PIN 4
#define DHT_TYPE DHT22
DHT dht(DHT_PIN, DHT_TYPE);

const int FAN_ENA_PIN = 10;
const int FAN_IN1_PIN = 11;
const int FAN_IN2_PIN = 12;

// ========= INTERVALS =========
const unsigned long SENSOR_PUBLISH_INTERVAL = 5000;
const unsigned long HEARTBEAT_INTERVAL      = 15000;
const unsigned long WIFI_RECONNECT_INTERVAL = 5000;
const unsigned long MQTT_RECONNECT_INTERVAL = 5000;

// ========= GLOBALS =========
WiFiClient espClient;
PubSubClient mqtt(espClient);

bool ledState = false;
bool fanState = false;
bool autoFanMode = true;

float tempHigh = 28.0;
float tempLow  = 27.0;
float humHigh  = 70.0;
float humLow   = 65.0;

unsigned long tLastSensor = 0, tLastHeartbeat = 0, tLastWifiChk = 0, tLastMqttChk = 0;

String topicSensorData, topicDeviceState, topicDeviceCmd, topicSysOnline;

// ========= SETUP =========
void setup() {
  Serial.begin(115200);
  Serial.println("\n=== ESP32-S3 IoT + MQTT + InfluxDB ===");

  pinMode(LED_PIN, OUTPUT);
  pinMode(FAN_ENA_PIN, OUTPUT);
  pinMode(FAN_IN1_PIN, OUTPUT);
  pinMode(FAN_IN2_PIN, OUTPUT);

  digitalWrite(LED_PIN, LOW);

  topicSensorData  = String(TOPIC_NS) + "/sensor/data";
  topicDeviceState = String(TOPIC_NS) + "/device/state";
  topicDeviceCmd   = String(TOPIC_NS) + "/device/cmd";
  topicSysOnline   = String(TOPIC_NS) + "/sys/online";

  dht.begin();
  Serial.println("[DHT] Initialized.");

  connectWiFi();
  mqttInit();
  mqttConnect();
}

// ========= LOOP =========
void loop() {
  unsigned long now = millis();
  if (mqtt.connected()) mqtt.loop();

  if (now - tLastWifiChk >= WIFI_RECONNECT_INTERVAL) {
    tLastWifiChk = now;
    if (WiFi.status() != WL_CONNECTED) connectWiFi();
  }
  if (now - tLastMqttChk >= MQTT_RECONNECT_INTERVAL) {
    tLastMqttChk = now;
    if (WiFi.status() == WL_CONNECTED && !mqtt.connected()) mqttConnect();
  }
  if (now - tLastSensor >= SENSOR_PUBLISH_INTERVAL) {
    tLastSensor = now;
    publishSensor();
    if (autoFanMode) handleAutoFan();
  }
  if (now - tLastHeartbeat >= HEARTBEAT_INTERVAL) {
    tLastHeartbeat = now;
    publishState();
  }
  delay(10);
}

// ========= INFLUXDB LOGGING =========
void sendToInflux(float temperature, float humidity, bool fan, bool light) {
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  http.begin(INFLUXDB_URL);
  http.addHeader("Content-Type", "text/plain");
  http.addHeader("Authorization", String("Token ") + INFLUXDB_TOKEN);

  String data = "iot_data,device=" + String(DEVICE_ID) +
                " temperature=" + String(temperature, 1) + 
                ",humidity=" + String(humidity, 1) +
                ",fan=" + String(fan ? 1 : 0) +
                ",light=" + String(light ? 1 : 0);

  int code = http.POST(data);
  Serial.printf("[InfluxDB] POST %s | Code: %d\n", data.c_str(), code);
  http.end();
}

// ========= GPIO CONTROL =========
void setLed(bool on) {
  ledState = on;
  digitalWrite(LED_PIN, ledState ? HIGH : LOW);
  Serial.printf("[LED] %s\n", ledState ? "ON" : "OFF");
}

void setFan(bool on) {
  fanState = on;
  if (on) {
    digitalWrite(FAN_IN1_PIN, HIGH);
    digitalWrite(FAN_IN2_PIN, LOW);
    analogWrite(FAN_ENA_PIN, 255);
  } else {
    digitalWrite(FAN_IN1_PIN, LOW);
    digitalWrite(FAN_IN2_PIN, LOW);
    analogWrite(FAN_ENA_PIN, 0);
  }
  Serial.printf("[FAN] %s\n", fanState ? "ON" : "OFF");
}

// ======== AUTO FAN ========
void handleAutoFan() {
  float t = dht.readTemperature();
  float h = dht.readHumidity();
  if (isnan(t) || isnan(h)) {
    Serial.println("[AUTO FAN] DHT read failed!");
    return;
  }

  if (fanState) {
    if (t <= tempLow && h <= humLow) setFan(false);
  } else {
    if (t >= tempHigh || h >= humHigh) setFan(true);
  }

  Serial.printf("[AUTO FAN] T=%.1f°C H=%.1f%% | Fan=%s\n", t, h, fanState ? "ON" : "OFF");
}

// ========= WIFI & MQTT =========
void connectWiFi() {
  Serial.printf("[WiFi] Connecting to %s\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int retry = 0;
  while (WiFi.status() != WL_CONNECTED && retry++ < 40) { delay(250); Serial.print("."); }
  if (WiFi.status() == WL_CONNECTED)
    Serial.printf("\n[WiFi] OK  IP=%s\n", WiFi.localIP().toString().c_str());
  else Serial.println("\n[WiFi] FAILED");
}

void mqttInit() {
  const char* host = USE_LOCAL_BROKER ? MQTT_HOST_LOCAL : MQTT_HOST_PUBLIC;
  mqtt.setServer(host, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setKeepAlive(30);
  mqtt.setBufferSize(512);
  Serial.printf("[MQTT] broker=%s:%d\n", host, MQTT_PORT);
}

void mqttConnect() {
  if (WiFi.status() != WL_CONNECTED) return;
  const char* host = USE_LOCAL_BROKER ? MQTT_HOST_LOCAL : MQTT_HOST_PUBLIC;
  Serial.printf("[MQTT] Connecting -> %s:%d\n", host, MQTT_PORT);

  StaticJsonDocument<128> lwt;
  lwt["status"] = "disconnected";
  lwt["online"] = false;
  String lwtPayload; serializeJson(lwt, lwtPayload);

  bool ok = mqtt.connect(DEVICE_ID, topicSysOnline.c_str(), 1, true, lwtPayload.c_str());
  if (!ok) { Serial.printf("[MQTT] FAILED state=%d\n", mqtt.state()); return; }

  Serial.println("[MQTT] Connected");
  mqtt.subscribe(topicDeviceCmd.c_str(), 1);
  publishOnline(true);
  publishState();
}

// ========= PUBLISH =========
void publishOnline(bool online) {
  if (!mqtt.connected()) return;
  StaticJsonDocument<128> doc;
  doc["status"] = online ? "connected" : "disconnected";
  doc["online"] = online;
  doc["uptime"] = millis() / 1000;
  String payload; serializeJson(doc, payload);
  mqtt.publish(topicSysOnline.c_str(), payload.c_str(), true);
}

void publishState() {
  if (!mqtt.connected()) return;
  StaticJsonDocument<256> doc;
  doc["ts"] = millis();
  doc["light"] = ledState ? "on" : "off";
  doc["fan"] = fanState ? "on" : "off";
  doc["autoFan"] = autoFanMode;
  doc["rssi"] = WiFi.RSSI();
  doc["fw"] = FIRMWARE_VERSION;
  String payload; serializeJson(doc, payload);
  mqtt.publish(topicDeviceState.c_str(), payload.c_str(), true);
}

void publishSensor() {
  if (!mqtt.connected()) return;
  float t = dht.readTemperature();
  float h = dht.readHumidity();

  if (isnan(t) || isnan(h)) {
    Serial.println("[DHT] Failed to read from sensor!");
    return;
  }

  StaticJsonDocument<256> doc;
  doc["ts"] = millis();
  doc["temp"] = t;
  doc["humidity"] = h;
  doc["fan"] = fanState ? "ON" : "OFF";
  doc["light"] = ledState ? "ON" : "OFF";

  String payload;
  serializeJson(doc, payload);
  mqtt.publish(topicSensorData.c_str(), payload.c_str(), false);
  Serial.printf("[PUB] %s %s\n", topicSensorData.c_str(), payload.c_str());

  sendToInflux(t, h, fanState, ledState);
}

// ========= MQTT CALLBACK =========
void handleCommand(const String& msg) {
  StaticJsonDocument<256> doc;
  if (deserializeJson(doc, msg)) return;

  bool changed = false;
  if (doc.containsKey("light")) {
    String act = doc["light"];
    if (act == "on") setLed(true);
    else if (act == "off") setLed(false);
    else if (act == "toggle") setLed(!ledState);
    changed = true;
  }
  if (doc.containsKey("fan")) {
    String act = doc["fan"];
    if (act == "on") { setFan(true); autoFanMode = false; }
    else if (act == "off") { setFan(false); autoFanMode = false; }
    else if (act == "toggle") { setFan(!fanState); autoFanMode = false; }
    changed = true;
  }
  if (doc.containsKey("autoFan")) {
    autoFanMode = doc["autoFan"];
    Serial.printf("[AUTO FAN] Mode: %s\n", autoFanMode ? "AUTO" : "MANUAL");
  }
  if (changed) publishState();
}

void mqttCallback(char* topic, byte* payload, unsigned int len) {
  String msg; msg.reserve(len + 1);
  for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
  Serial.printf("[RX] %s %s\n", topic, msg.c_str());
  if (String(topic) == topicDeviceCmd) handleCommand(msg);
}
