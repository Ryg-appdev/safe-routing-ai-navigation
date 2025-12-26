# 06_API仕様書.md

## 1. API呼び出しシーケンス

```mermaid
sequenceDiagram
    participant iOS as 📱 iOS App
    participant CF as ☁️ Cloud Functions
    participant W as 🌧️ OpenWeatherMap
    participant H as 🗺️ ハザードマップ
    participant R as 🛣️ Google Routes
    participant G3 as 🤖 Gemini 3

    iOS->>CF: POST /findSafeRoute
    activate CF
    
    par 並列データ取得
        CF->>W: 気象データ取得
        W-->>CF: rain, wind
        CF->>H: 浸水リスク取得
        H-->>CF: flood_depth
    end
    
    CF->>G3: リスク評価
    G3-->>CF: riskScore, avoidanceTags
    
    CF->>R: computeRoutes (alternatives: true)
    R-->>CF: routes[]
    
    CF->>G3: ナレーション生成
    G3-->>CF: narrative
    
    CF-->>iOS: RouteResponse
    deactivate CF
```

## 2. Backend Endpoints (Cloud Functions)

### `POST /findSafeRoute`
- **概要**: メインの経路探索API。
- **Auth**: API Key (Header: `X-App-Check`)
- **Request**:
    ```json
    {
      "origin": {"lat": 35.6812, "lng": 139.7671},
      "destination": {"lat": 35.6591, "lng": 139.7006},
      "mode": "EMERGENCY"
    }
    ```
- **Response (Success)**:
    ```json
    {
      "routes": [
        {
          "polyline": "encoded_polyline_string",
          "summary": "高台経由ルート",
          "durationSeconds": 900,
          "safetyScore": 85,
          "warnings": ["浸水エリア回避"]
        }
      ],
      "narrative": "大雨を検知しました。高台を経由する安全なルートを設定しました。",
      "thinkingProcessLog": ["Fetching weather...", "Risk: HIGH", "Rerouting..."],
      "riskAssessment": {
        "level": "HIGH",
        "factors": ["Rain > 50mm/h", "Flood Risk"]
      }
    }
    ```
- **Response (Error / Fallback)**:
    ```json
    {
      "routes": [...],
      "narrative": "一部データの取得に失敗しましたが、安全なルートを設定しました。",
      "thinkingProcessLog": ["[Warning] Weather API timeout.", "Using cached data."],
      "error": {
        "code": "PARTIAL_DATA_FAILURE",
        "message": "OpenWeatherMap API timed out."
      }
    }
    ```

### `POST /analyzeRouteSafety` (Async Optional)

```mermaid
sequenceDiagram
    participant iOS as 📱 iOS App
    participant CF as ☁️ Cloud Functions
    participant SV as 📷 Street View
    participant G3 as 🤖 Gemini Vision

    iOS->>CF: POST /analyzeRouteSafety
    loop 各地点
        CF->>SV: GET image
        SV-->>CF: 画像データ
        CF->>G3: 安全性解析
        G3-->>CF: score, tags
        CF-->>iOS: SSE push
    end
```

- **概要**: 指定された座標リストの「視覚的安全性」を解析する。
- **Timeout**: 各地点につき最大3秒。失敗時はスキップ。
- **Request**:
    ```json
    {
      "points": [{"lat": 35.658, "lng": 139.701}, ...]
    }
    ```
- **Response** (Stream/JSON):
    ```json
    [
      {"id": 1, "score": 80, "tags": ["Bright", "Wide Road"]},
      {"id": 2, "score": null, "tags": [], "error": "StreetView unavailable"}
    ]
    ```

## 3. External API Usage

### Google Routes API (`v2.computeRoutes`)

```mermaid
flowchart LR
    A[Request] --> B[computeRoutes]
    B --> C{成功?}
    C -->|Yes| D[routes[] 返却]
    C -->|No| E[Mock Route 返却]
```

- **Method**: POST
- **FieldMask**: `routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline`
- **Note**: `X-Goog-FieldMask` ヘッダーが必須。
- **Fallback**: 失敗時は事前定義のモックルートを使用。

### OpenWeatherMap (One Call 3.0)
- **Endpoint**: `https://api.openweathermap.org/data/3.0/onecall`
- **Params**: `lat`, `lon`, `exclude=minutely,daily`, `appid`
- **Fallback**: 失敗時はキャッシュデータを使用。キャッシュもない場合は `rain: 0, wind: 0` として処理継続。

### Google Street View Static API
- **Endpoint**: `https://maps.googleapis.com/maps/api/streetview`
- **Params**: `size=600x400`, `location=lat,lng`, `source=outdoor`, `key`
- **Fallback**: 画像取得失敗時はその地点をスキップ。
