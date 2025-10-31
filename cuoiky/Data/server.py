import csv
import json
from datetime import datetime
from paho import mqtt
from paho.mqtt import client as mqtt_client

BROKER = 'broker.hivemq.com'
PORT = 1883
TOPIC = 'demo/room1/sensor/data'  # đúng topic ESP gửi
CLIENT_ID = 'iot_logger_luong'
CSV_FILE = 'iot_log.csv'


def on_connect(client, userdata, flags, reason_code, properties=None):
    if reason_code == 0:
        print("✅ MQTT: Kết nối thành công.")
        client.subscribe(TOPIC)
        print(f"Đang lắng nghe dữ liệu tại topic: {TOPIC}")
    else:
        print("❌ Kết nối thất bại, mã lỗi:", reason_code)


def on_message(client, userdata, msg):
    try:
        payload = msg.payload.decode()
        print("📩 Nhận:", payload)

        data = json.loads(payload)
        temp = data.get("temp") or data.get("temperature")
        hum = data.get("humidity") or data.get("hum")
        fan = data.get("fan", "unknown")
        light = data.get("light", "unknown")

        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        with open(CSV_FILE, mode='a', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow([timestamp, temp, hum, fan, light])

        print(f"→ Ghi log: {timestamp} | T={temp}°C | H={hum}% | Quạt={fan} | Đèn={light}")

    except Exception as e:
        print("⚠️ Lỗi khi xử lý message:", e)


def create_client():
    """Tự động xử lý sự khác biệt giữa paho-mqtt v1 và v2."""
    try:
        # Cách mới (v2)
        return mqtt_client.Client(client_id=CLIENT_ID, callback_api_version=mqtt_client.CallbackAPIVersion.v5)
    except Exception:
        # Cách cũ (v1)
        return mqtt_client.Client(CLIENT_ID)


def main():
    print("🚀 Khởi động MQTT Logger...")
    client = create_client()
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(BROKER, PORT)
    client.loop_forever()


if __name__ == '__main__':
    # Tạo file CSV nếu chưa có
    try:
        with open(CSV_FILE, 'x', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(["Thời gian", "Nhiệt độ (°C)", "Độ ẩm (%)", "Trạng thái Quạt", "Trạng thái Đèn"])
    except FileExistsError:
        pass

    main()
