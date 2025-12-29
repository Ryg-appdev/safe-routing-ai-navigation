#!/bin/bash

# バックエンドの動作確認用スクリプト
# 東京駅から新宿駅までのルート探索リクエストを送信します

echo "📡 Sending request to local backend (http://127.0.0.1:8080)..."
echo "--- Request Body ---"
echo '{"origin": "渋谷駅", "destination": "原宿駅", "context": {"mode": "NORMAL"}}'
echo "--------------------"

curl -X POST http://127.0.0.1:8080 \
  -H "Content-Type: application/json" \
  -d '{"origin": "渋谷駅", "destination": "原宿駅", "context": {"mode": "NORMAL"}}' | json_pp

echo -e "\n--------------------"
echo "✅ Request completed."
