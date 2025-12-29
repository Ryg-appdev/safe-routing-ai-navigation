# 全体フローにおける Navigator の位置づけ

`The Navigator` は、司令塔 (`Sentinel`) からの実務命令を受けて、具体的な計算と調査を行う「実行部隊」です。

```mermaid
graph TD
    %% Actors
    USER(("👤 User"))
    
    subgraph BRAIN ["🧠 The Sentinel (司令塔)"]
        SENTINEL["意思決定と指示"]
    end
    
    subgraph WORKER ["🛠️ The Navigator (探索・実務)"]
        NAV_ROUTE["ルート検索"]
        NAV_LOGIC["リスク評価ロジック"]
        
        NAV_ROUTE --> NAV_LOGIC
    end
    
    subgraph FACE ["🛡️ The Guardian (対話)"]
        GUARD["結果の翻訳/伝達"]
    end
    
    %% APIs
    GMAPS["Google Routes API"]
    SOLAR["Solar API"]
    CRIME["Crime DB"]

    %% Flow
    USER -->|"安全な道教えて！"| SENTINEL
    
    SENTINEL -->|"探索せよ"| NAV_ROUTE
    
    NAV_ROUTE -.-> GMAPS
    NAV_LOGIC -.-> SOLAR
    NAV_LOGIC -.-> CRIME
    
    NAV_LOGIC -->|"計算結果 (Score: 30点)"| SENTINEL
    
    SENTINEL -->|"スコア30点か... Guardian、警告付きで伝えて"| GUARD
    
    GUARD -->|"⚠️ 危険です！この道は避けましょう"| USER

    %% Styling
    style WORKER fill:#e1f5fe,stroke:#01579b,stroke-width:2px
    style NAV_LOGIC fill:#fff9c4,stroke:#fbc02d,stroke-width:4px
```

## 今やっていること
この図の **黄色い枠 (`リスク評価ロジック`)** の中身を実装しようとしています。
ここが出来上がらないと、Sentinelは判断材料（スコア）を得られず、Guardianも何も言えません。
