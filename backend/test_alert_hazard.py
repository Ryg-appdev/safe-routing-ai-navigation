#!/usr/bin/env python3
"""
警報連動ハザードチェックの動作確認スクリプト
Navigator の警報連動ロジックをテスト
"""

import asyncio
import sys
import os
from dotenv import load_dotenv

# .envから環境変数を読み込み
load_dotenv('/Users/ryoga/Projects/第4回 Agentic AI Hackathon with Google Cloud/backend/.env')

sys.path.insert(0, '/Users/ryoga/Projects/第4回 Agentic AI Hackathon with Google Cloud/backend/app')

from agents.navigator import NavigatorAgent
from google import genai

async def test_alert_linked_hazard_checking():
    print("=== 警報連動ハザードチェック テスト ===\n")
    
    # 1. Navigatorの初期化
    client = genai.Client()
    navigator = NavigatorAgent(client)
    
    # テスト地点（横浜駅周辺 - 浸水リスクあり）
    test_point = {"lat": 35.5389, "lng": 139.7411}
    elevation = 3.0  # 低地
    
    print(f"テスト地点: {test_point}")
    print(f"標高: {elevation}m\n")
    
    # --- テスト1: 警報なし ---
    print("【テスト1】警報なし")
    navigator.active_alerts = []
    result = await navigator._analyze_single_point(0, test_point, elevation)
    print(f"  スコア: {result['score']}")
    print(f"  リスク: {result['risks']}")
    has_flood_hazard = any("FLOOD_HAZARD" in r for r in result['risks'])
    print(f"  → 浸水ハザード検出: {'あり ⚠️' if has_flood_hazard else 'なし ✅'}")
    print()
    
    # --- テスト2: 大雨警報発令 ---
    print("【テスト2】大雨警報発令中")
    navigator.active_alerts = ["大雨警報"]
    result = await navigator._analyze_single_point(0, test_point, elevation)
    print(f"  スコア: {result['score']}")
    print(f"  リスク: {result['risks']}")
    has_flood_hazard = any("FLOOD_HAZARD" in r for r in result['risks'])
    print(f"  → 浸水ハザード検出: {'あり ✅' if has_flood_hazard else 'なし ⚠️'}")
    print()
    
    # --- テスト3: 津波警報発令 ---
    print("【テスト3】津波警報発令中")
    navigator.active_alerts = ["津波警報"]
    result = await navigator._analyze_single_point(0, test_point, elevation)
    print(f"  スコア: {result['score']}")
    print(f"  リスク: {result['risks']}")
    has_tsunami_hazard = any("TSUNAMI_HAZARD" in r for r in result['risks'])
    print(f"  → 津波ハザード検出: {'あり ✅' if has_tsunami_hazard else 'なし（この地点はリスクなし）'}")
    print()
    
    # --- テスト4: 土砂災害警戒情報発令 ---
    print("【テスト4】土砂災害警戒情報発令中")
    navigator.active_alerts = ["土砂災害警戒情報"]
    result = await navigator._analyze_single_point(0, test_point, elevation)
    print(f"  スコア: {result['score']}")
    print(f"  リスク: {result['risks']}")
    has_landslide_hazard = any("LANDSLIDE_HAZARD" in r for r in result['risks'])
    print(f"  → 土砂災害ハザード検出: {'あり ✅' if has_landslide_hazard else 'なし（この地点はリスクなし）'}")
    print()
    
    print("=== テスト完了 ===")

if __name__ == "__main__":
    asyncio.run(test_alert_linked_hazard_checking())
