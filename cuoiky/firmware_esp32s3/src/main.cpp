// ==================== ESP32-S3 IoT (GPIO2 + DHT22 + L298N Fan + MQTT) ====================
#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <DHT.h>

// ========= USER CONFIG =========
const char* WIFI_SSID     = "MEMORY COFFEE";
const char* WIFI_PASSWORD = "Memory123@";

static const bool USE_LOCAL_BROKER = false;
const char* MQTT_HOST_PUBLIC = "broker.hivemq.com";
const char* MQTT_HOST_LOCAL  = "192.168.1.10";
const int   MQTT_PORT        = 1883;

// MQTT auth (để trống nếu không dùng)
const char* MQTT_USER = nullptr;
const char* MQTT_PASS = nullptr;

// ⚡ ĐỔI NAMESPACE để tránh dữ liệu ảo
const char* TOPIC_NS = "luong_iot/room1";

// Device info
const char* DEVICE_ID        = "esp32s3_luong_001";
const char* FIRMWARE_VERSION = "luongfw-1.1.0";

// ========= PIN MAP =========
const int LED_PIN = 2;
const bool LED_ACTIVE_HIGH = true;
#define DHT_PIN  4
#define DHT_TYPE DHT22
DHT dht(DHT_PIN, DHT_TYPE);

// L298N Fan
const int FAN_ENA_PIN = 10;
const int FAN_IN1_PIN = 11;
const int FAN_IN2_PIN = 12;
bool fanState = false;

// ========= INTERVALS =========
const unsigned long SENSOR_PUBLISH_INTERVAL = 5000;
const unsigned long HEARTBEAT_INTERVAL      = 15000;
const unsigned long WIFI_RECONNECT_INTERVAL = 5000;
const unsigned long MQTT_RECONNECT_INTERVAL = 5000;

// ========= GLOBALS =========
WiFiClient espClient;
PubSubClient mqtt(espClient);

bool ledState = true;
unsigned long tLastSensor = 0, tLastHeartbeat = 0, tLastWifiChk = 0, tLastMqttChk = 0;

String topicSensorData, topicDeviceState, topicDeviceCmd, topicSysOnline;

// ========= SERIAL =========
void serialInit() {
    Serial.begin(115200);
    unsigned long start = millis();
    while (!Serial && millis() - start < 4000) delay(10);
    Serial.println("\n=== ESP32-S3 IoT (GPIO2 + DHT22 + L298N Fan + MQTT) ===");
    Serial.printf("[BOOT] FW=%s  NS=%s\n", FIRMWARE_VERSION, TOPIC_NS);
}

// ========= GPIO =========
inline void writePinGuaranteed(int pin, bool activeHigh, bool on) {
    if (pin < 0) return;
    digitalWrite(pin, activeHigh ? (on ? HIGH : LOW) : (on ? LOW : HIGH));
}

inline void setLed(bool on) {
    ledState = on;
    writePinGuaranteed(LED_PIN, LED_ACTIVE_HIGH, ledState);
    Serial.printf("[LED] %s\n", ledState ? "ON" : "OFF");
}

void setFan(bool on) {
    fanState = on;
    if (on) {
        digitalWrite(FAN_IN1_PIN, HIGH);
        digitalWrite(FAN_IN2_PIN, LOW);
        analogWrite(FAN_ENA_PIN, 255); // full speed
    } else {
        digitalWrite(FAN_IN1_PIN, LOW);
        digitalWrite(FAN_IN2_PIN, LOW);
        analogWrite(FAN_ENA_PIN, 0); // stop
    }
    Serial.printf("[FAN] %s\n", fanState ? "ON" : "OFF");
}

void initGPIO() {
    pinMode(LED_PIN, OUTPUT);
    pinMode(FAN_ENA_PIN, OUTPUT);
    pinMode(FAN_IN1_PIN, OUTPUT);
    pinMode(FAN_IN2_PIN, OUTPUT);

    digitalWrite(LED_PIN, HIGH); delay(150);
    digitalWrite(LED_PIN, LOW); delay(150);
    digitalWrite(LED_PIN, HIGH);
    setLed(true);
    setFan(false);

    Serial.printf("[GPIO] LED_PIN=%d, DHT_PIN=%d, FAN_ENA=%d, IN1=%d, IN2=%d\n",
                  LED_PIN, DHT_PIN, FAN_ENA_PIN, FAN_IN1_PIN, FAN_IN2_PIN);
}

// ========= TOPICS =========
void initTopics() {
    topicSensorData  = String(TOPIC_NS) + "/sensor/data";
    topicDeviceState = String(TOPIC_NS) + "/device/state";
    topicDeviceCmd   = String(TOPIC_NS) + "/device/cmd";
    topicSysOnline   = String(TOPIC_NS) + "/sys/online";
    Serial.println("[MQTT Topics]");
    Serial.println("  " + topicSensorData);
    Serial.println("  " + topicDeviceState);
    Serial.println("  " + topicDeviceCmd);
    Serial.println("  " + topicSysOnline);
}

// ========= WIFI =========
void connectWiFi() {
    Serial.printf("[WiFi] Connecting to %s\n", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; ++i) { delay(250); Serial.print("."); }
    if (WiFi.status() == WL_CONNECTED)
        Serial.printf("\n[WiFi] OK  IP=%s RSSI=%d\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
    else Serial.println("\n[WiFi] FAILED");
}

// ========= MQTT =========
void publishOnline(bool online) {
    if (!mqtt.connected()) return;
    StaticJsonDocument<128> doc;
    doc["status"] = online ? "connected" : "disconnected";
    doc["online"] = online;
    doc["uptime"] = millis() / 1000;
    String payload; serializeJson(doc, payload);
    mqtt.publish(topicSysOnline.c_str(), payload.c_str(), true);
    Serial.printf("[PUB] %s %s\n", topicSysOnline.c_str(), payload.c_str());
}

void publishState() {
    if (!mqtt.connected()) return;
    StaticJsonDocument<192> doc;
    doc["ts"] = millis();
    doc["light"] = ledState ? "on" : "off";
    doc["fan"] = fanState ? "on" : "off";
    doc["rssi"] = WiFi.RSSI();
    doc["fw"] = FIRMWARE_VERSION;
    String payload; serializeJson(doc, payload);
    mqtt.publish(topicDeviceState.c_str(), payload.c_str(), true);
    Serial.printf("[PUB] %s %s\n", topicDeviceState.c_str(), payload.c_str());
}

void publishSensor() {
    if (!mqtt.connected()) return;
    float h = dht.readHumidity();
    float t = dht.readTemperature();
    StaticJsonDocument<192> doc;
    doc["ts"] = millis();
    if (!isnan(h) && !isnan(t)) {
        doc["humidity"] = round(h * 10) / 10.0;
        doc["temp"] = round(t * 10) / 10.0;
    } else {
        doc["humidity"] = nullptr;
        doc["temp"] = nullptr;
    }
    doc["light"] = nullptr;
    String payload; serializeJson(doc, payload);
    mqtt.publish(topicSensorData.c_str(), payload.c_str(), false);
    Serial.printf("[PUB] %s %s\n", topicSensorData.c_str(), payload.c_str());
}

void handleCommand(const String& msg) {
    StaticJsonDocument<192> doc;
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
        if (act == "on") setFan(true);
        else if (act == "off") setFan(false);
        else if (act == "toggle") setFan(!fanState);
        changed = true;
    }

    if (changed) publishState();
}

void mqttCallback(char* topic, byte* payload, unsigned int len) {
    String msg; msg.reserve(len + 1);
    for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
    Serial.printf("[RX] %s %s\n", topic, msg.c_str());
    if (String(topic) == topicDeviceCmd) handleCommand(msg);
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

// ========= LOOP =========
void setup() {
    serialInit();
    initGPIO();
    initTopics();
    dht.begin();
    connectWiFi();
    mqttInit();
    mqttConnect();
    Serial.println("[BOOT] setup done");
}

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
    }
    if (now - tLastHeartbeat >= HEARTBEAT_INTERVAL) {
        tLastHeartbeat = now;
        publishState();
    }
    delay(10);
}
