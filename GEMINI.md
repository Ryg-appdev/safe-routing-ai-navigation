# Situation-Adaptive Safe Routing AI Navigation プロジェクトルール

> [!IMPORTANT]
> **【メタ・ルール：絶対遵守】**
> 1. **タスク開始時**: 必ずタスクのゴールと手順を確認・定義してから着手すること。
> 2. **バグ修正時**: 推測での修正は厳禁。必ず原因を特定するためのログ出力や調査を行い、エビデンスに基づいて修正すること。
> 3. **完了報告時**: 必ず実装した内容と、確認した動作（テスト結果）をセットで報告すること。

> [!IMPORTANT]
> **【最重要】 `notify_user` で報告を行う前に、必ず実装内容とドキュメントの整合性を確認してください。**

## プロジェクト概要
- **プロダクト名**: Situation-Adaptive Safe Routing AI Navigation
- **コンセプト**: 「いつもの移動は"安心寄り"に、非常時は"生存寄り"に切り替わるナビ」
- **ターゲット**: Google Cloud Japan AI Hackathon Vol.4 審査員
- **プラットフォーム**: Flutter (iOS / Android), Backend (Google ADK / Cloud Run)
- **技術スタック**: 
  - **Frontend**: Flutter (Dart), google_maps_flutter
  - **Backend**: Python, Google ADK, Cloud Run
  - **AI**: Vertex AI (Gemini)
  - **External APIs**:
    - **Routing**: Google Routes API
    - **Weather**: OpenWeatherMap API
    - **Safety**: 警視庁犯罪情報オープンデータ (Statistics) / Google Street View Static API
    - **Disaster**: 国土交通省ハザードマップ (Tile/API)

## 主要機能（MVP）
1. **モード切替** - 日常（青）⇔ 非常時（赤）のトグルスイッチ + **気象警報による自動切替**
2. **防犯ヒートマップ（日常）** - 警視庁オープンデータに基づく安全エリア可視化
3. **リスク回避ルート探索（非常時）** - 浸水・土砂災害・津波を回避するルート提案
4. **AIナレーション** - Vertex AI (Gemini) によるルート選択理由の解説
5. **思考ログ表示** - AIの推論プロセスを可視化（デモ映え機能）

## ディレクトリ構成
```
/
├── backend/            # Google ADK (Python)
│   ├── agents/         # Agent Modules
│   ├── services/       # External API Clients
│   └── main.py         # Cloud Run Entry Point
├── flutter_app/        # Flutter App (iOS / Android)
│   ├── lib/
│   │   ├── screens/    # UI Screens
│   │   ├── providers/  # State Management (Riverpod)
│   │   ├── services/   # API Clients
│   │   └── models/     # Data Models
│   └── pubspec.yaml
└── Docs/               # プロジェクトドキュメント
    ├── 確定/           # 仕様書・設計書
    └── 計画/           # 実装計画・ログ
```

## 言語設定
- 常に日本語で応答してください
- コードコメントも日本語で書いてください（変数名・関数名は英語）
- 技術用語は必要に応じて英語のまま使用してもOKです

## 相互理解・学習のためのルール (User-Centric Development)
> [!IMPORTANT]
> ユーザーが「コードを理解しながら進める」ことを最優先する。
- **Explanation First**: コードを書く前に、必ず「実装するロジックの概要」と「なぜそのコードが必要か」を説明し、合意を得ること。
- **Step-by-Step Implementation**: 巨大なコードを一気に生成せず、論理的なブロックごとに区切って実装・解説すること。
- **Japanese Comments**: コードの意図を理解機しやすくするため、重要なロジック部分には日本語で丁寧なコメントを記述すること。
- **Diagrams**: 複雑なロジック（リスク評価アルゴリズム等）は、必ず Mermaid 等で図解して可視化すること。
- **Code Walkthrough**: 実装完了後、単に「完了しました」で終わらせず、実装したコードの主要部分（どの関数が何をしているか）を丁寧に解説すること。
- **Documentation First**: 実装は必ず「確定した仕様書 (`Docs/確定/`)」に従うこと。実装中に仕様との乖離が必要になった場合、**コードを書く前にドキュメントを更新し、ユーザーの合意を得る**こと。

## コーディングスタイル

### General
- **1タスク・1実装・1確認**の徹底
- 既存コードのスタイル・パターンに合わせる

### Backend (Python / Google ADK)
- Pythonの型ヒントを最大限活用する
- Pydanticを使用して入出力を厳密に定義する
- エージェント（Agent）は単一責任の原則に従って分割する

### Frontend (Flutter / Dart)
- MVVMアーキテクチャを採用する（Provider / Riverpod）
- google_maps_flutter でマップを表示
- モードによるテーマ切り替え（青/赤）は `ThemeProvider` で一元管理する

## セキュリティ・AI倫理 (Important)
- **APIキー管理**: APIキーは絶対にコードにハードコードしないこと。必ず環境変数 (`.env`) を使用する。
  - **Git混入防止**: `.env` やキーを含むファイルは必ず `.gitignore` に追加する。
- **AI免責 (Disclaimer)**: ナビゲーション結果はあくまで参考情報であり、最終的な判断（特に避難時）はユーザー自身の判断および公式情報に従うことをUI上で明示する。
- **ハルシネーション対策**: 存在しないルートを案内しないよう、Geminiの出力は可能な限りGoogle Routesの正規化されたデータに基づいて構成する。

## 品質管理 (QA)
- **Realism First**: デモの見栄えよりも、機能の実用性と論理的な正しさを優先する。「デモのために挙動を歪める」ことはしない。
- **実機テスト**: GPS連動機能は、必ず実機（またはシミュレータのLocation機能）で動作確認を行う。
- **ドキュメントが正** - `Docs/確定/` 配下のドキュメントが仕様の正となる
- **ドキュメント更新 → 実装** - 仕様変更時は、コードを書く前にドキュメントを更新する
- **Plan First** - 複雑な機能実装前には計画（Plan）を立て、合意を得てから進める

## コミットルール
- **コミットメッセージは日本語で記述する**
- プレフィックス（`feat:`, `fix:`, `docs:` 等）は英語、内容は日本語
  - 例: `feat: 非常時モードのRisk Evaluatorフロー実装`

## 機能追加・バグ修正時の報告テンプレート

### 機能追加報告
```markdown
### 機能追加報告

1. **実装機能の概要**
   - （何を実装したか）

2. **変更内容**
   - （主要な変更ファイルと役割）

3. **動作確認方法**
   - （どのような検証を行ったか）
```

### バグ修正報告
```markdown
### バグ修正報告

1. **特定した原因**
   - （ログ・コード解析に基づく原因）

2. **修正内容**
   - （修正したファイルと具体的な変更内容）

3. **動作確認方法**
   - （検証手順）
```

## UIガイド（Situation-Adaptive）

### テーマカラー定義
| モード | Primary Color | Background | 雰囲気 |
|---|---|---|---|
| **日常 (Normal)** | `#007AFF` (Blue) | White / Light Gray | 安心、清潔、明るい |
| **非常時 (Emergency)** | `#FF3B30` (Red) | Black / Dark Gray | 警戒、緊急、視認性重視 |

### Google Maps Style
- **Normal**: 標準（Standard）または明るいカスタムスタイル
- **Emergency**: ダークモードベース、建物等のノイズを減らし、ルートと危険エリアを強調するスタイル

## アーキテクチャ (True Agentic Architecture)

### 階層型マルチエージェント
本プロジェクトは、単一のLLMではなく、役割分担された複数のエージェント群によって動作する。

1.  **🕵️ The Sentinel (司令塔)**: ユーザーの文脈を理解し、適切な専門エージェントを呼び出す。推論（Reasoning）の中枢。
2.  **🗺️ The Navigator (探索)**: Google Routes API, Solar, Places, Crime DB等を駆使し、ルート探索と物理的リスク評価を行う。
3.  **👁️ The Analyst (視覚)**: 必要に応じてStreet Viewやカメラ映像を解析し、数値化できない「雰囲気（Vibe）」をスコア化する。
4.  **🛡️ The Guardian (守護)**: ユーザーへの対話インターフェース。緊急度に応じたペルソナ（Concierge / Tactical）で応答する。

### リスク評価ロジック (Bottle-neck Safety)
- **Route Sampling**: ルート全体ではなく、**50m間隔のポイント**に分解して評価する。
- **Bottle-neck Evaluation**: 平均点ではなく、**「最も危険な地点（ボトルネック）」のスコア**をルート全体のスコアとする。「99%安全でも1箇所真っ暗なら危険」と判定する。

## よく使うパターン (Google ADK / Python)

### Agent定義 (Sentinel Pattern)
```python
from google.adk import Agent

# Sentinel Agent (Dispatcher)
sentinel = Agent(
    name="sentinel",
    model="gemini-3-pro",
    instruction="""
    You are The Sentinel.
    Your goal is to PROTECT the user by planning the best course of action.
    Do not execute tools directly. Plan which agent (Navigator, Analyst, Guardian) to call.
    Output JSON with { thought, urgency, next_agent, instruction }.
    """
)
```
