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
- **コンセプト**: 「いつもの移動は“安心寄り”に、非常時は“生存寄り”に切り替わるナビ」
- **ターゲット**: Google Cloud Japan AI Hackathon Vol.4 審査員
- **プラットフォーム**: iOS (SwiftUI), Backend (Firebase Genkit)
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
1. **モード切替** - 日常（青）⇔ 非常時（赤）のトグルスイッチ
2. **防犯ヒートマップ（日常）** - 警視庁オープンデータに基づく安全エリア可視化
3. **リスク回避ルート探索（非常時）** - 大雨・浸水・（擬似）事故を回避するルート提案
4. **AIナレーション** - Gemini 3によるルート選択理由の解説
5. **思考ログ表示** - AIの推論プロセスを可視化（デモ映え機能）

## ディレクトリ構成
```
/
├── backend/            # Firebase Genkit (Agentic AI Layer)
│   ├── src/            # TypeScript Source
│   │   ├── flows/      # Genkit Flows (Agents)
│   │   └── lib/        # Shared Utilities
│   └── package.json
├── ios/                # iOS App (SwiftUI)
│   ├── App/            # App Entry Point
│   ├── Views/          # SwiftUI Views
│   ├── ViewModels/     # Presentation Logic
│   ├── Services/       # API Clients, Location Manager
│   └── Models/         # Data Models (Codable)
└── Docs/               # プロジェクトドキュメント
    ├── 確定/           # 仕様書・設計書
    └── 計画/           # 実装計画・ログ
```

## 言語設定
- 常に日本語で応答してください
- コードコメントも日本語で書いてください（変数名・関数名は英語）
- 技術用語は必要に応じて英語のまま使用してもOKです

## コーディングスタイル

### General
- **1タスク・1実装・1確認**の徹底
- 既存コードのスタイル・パターンに合わせる

### Backend (Genkit / TypeScript)
- TypeScriptの型システムを最大限活用する（`any` 禁止）
- Zodスキーマを使用して入出力を厳密に定義する
- エージェント（Flow）は単一責任の原則に従って分割する

### Frontend (iOS / Swift)
- MVVMアーキテクチャを採用する
- Google Maps SDKの実装は `UIViewRepresentable` でラップし、SwiftUIライフサイクルと適切に連携させる
- モードによるテーマ切り替え（青/赤）は `EnvironmentObject` または `ThemeManager` で一元管理する
### Frontend (iOS / Swift)
- MVVMアーキテクチャを採用する
- Google Maps SDKの実装は `UIViewRepresentable` でラップし、SwiftUIライフサイクルと適切に連携させる
- モードによるテーマ切り替え（青/赤）は `EnvironmentObject` または `ThemeManager` で一元管理する

## セキュリティ・AI倫理 (Important)
- **APIキー管理**: APIキーは絶対にコードにハードコードしないこと。必ず環境変数 (`.env`, `Info.plist` の注入フロー) を使用する。
  - **Git混入防止**: `.env` やキーを含むファイルは必ず `.gitignore` に追加する。
- **AI免責 (Disclaimer)**: ナビゲーション結果はあくまで参考情報であり、最終的な判断（特に避難時）はユーザー自身の判断および公式情報に従うことをUI上で明示する。
- **ハルシネーション対策**: 存在しないルートを案内しないよう、Geminiの出力は可能な限りGoogle Routesの正規化されたデータに基づいて構成する。

## 品質管理 (QA)
- **デモ映えチェック**: ハッカソン提出用デモ動画の見栄えを最優先する。画面遷移のスムーズさ、Thinking Logの流れる速度などを調整する。
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

## よく使うパターン (Genkit)

### Flow定義
```typescript
import { genkit, z } from 'genkit';
import { googleAI, gemini15Flash } from '@genkit-ai/googleai';

const ai = genkit({
  plugins: [googleAI()],
  model: gemini15Flash,
});

export const myFlow = ai.defineFlow(
  {
    name: 'myFlow',
    inputSchema: z.object({ input: z.string() }),
  },
  async (input) => {
    // Logic here
    return { result: "ok" };
  }
);
```
