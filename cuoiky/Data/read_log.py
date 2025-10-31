# ==================== read_log.py ====================
import csv
import os
from prettytable import PrettyTable
from collections import deque

LOG_FILE = "iot_log.csv"
MAX_ROWS = 5  # số dòng mới nhất muốn xem

def read_log():
    if not os.path.exists(LOG_FILE):
        print("Không tìm thấy file iot_log.csv. Hãy chạy server trước để tạo log.")
        return

    print("=== DỮ LIỆU LOG IOT (mới nhất) ===")

    try:
        with open(LOG_FILE, 'r', encoding='utf-8', errors='ignore', newline='') as f:
            reader = csv.DictReader(f)
            rows = deque(reader, maxlen=MAX_ROWS)
            headers = reader.fieldnames or []

        if not rows:
            print("(Không có dữ liệu trong log)")
            return

        def find_col(*options):
            for opt in options:
                for h in headers:
                    if opt.lower() in h.lower():
                        return h
            return ""

        col_time = find_col("time", "timestamp", "date")
        col_temp = find_col("temp", "temperature", "temp_c")
        col_hum = find_col("hum", "humidity", "hum_pct")
        col_fan = find_col("fan", "device", "motor")
        col_light = find_col("light", "status", "led")

        table = PrettyTable()
        table.field_names = ["Thời gian", "Nhiệt độ (°C)", "Độ ẩm (%)", "Quạt", "Đèn"]

        for row in rows:
            table.add_row([
                row.get(col_time, ""),
                row.get(col_temp, ""),
                row.get(col_hum, ""),
                row.get(col_fan, ""),
                row.get(col_light, "")
            ])

        print(table)

    except Exception as e:
        print(f"Lỗi khi đọc log: {e}")

if __name__ == "__main__":
    read_log()
