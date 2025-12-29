#!/usr/bin/env python3
"""
ハザードサービス動作確認スクリプト
洪水・津波・土砂災害のハザードマップAPIが正常に動作するか確認
"""

import asyncio
import sys
sys.path.insert(0, '/Users/ryoga/Projects/第4回 Agentic AI Hackathon with Google Cloud/backend/app')

async def test_flood_service():
    """洪水ハザードマップのテスト"""
    print("\n=== 洪水ハザードマップテスト ===")
    from services.flood_service import flood_service
    
    # テスト地点: 東京都江東区（浸水リスク高い地域）
    test_points = [
        (35.6584, 139.6817, "東京駅付近"),
        (35.5389, 139.7411, "横浜駅付近"),
        (35.6607, 139.7935, "東京湾沿い"),
    ]
    
    for lat, lng, name in test_points:
        is_risk, depth = await flood_service.check_flood_risk(lat, lng)
        if is_risk:
            print(f"⚠️ {name}: 浸水リスクあり (深さ: {depth})")
        else:
            print(f"✅ {name}: 浸水リスクなし")

async def test_tsunami_service():
    """津波ハザードマップのテスト"""
    print("\n=== 津波ハザードマップテスト ===")
    from services.tsunami_service import tsunami_service
    
    # テスト地点: 沿岸部
    test_points = [
        (35.4576, 139.6196, "横浜みなとみらい"),
        (35.5539, 139.7783, "お台場"),
        (35.6584, 139.6817, "東京駅付近（内陸）"),
    ]
    
    for lat, lng, name in test_points:
        is_risk, depth = await tsunami_service.check_tsunami_risk(lat, lng)
        if is_risk:
            print(f"⚠️ {name}: 津波リスクあり (深さ: {depth})")
        else:
            print(f"✅ {name}: 津波リスクなし")

async def test_landslide_service():
    """土砂災害ハザードマップのテスト"""
    print("\n=== 土砂災害ハザードマップテスト ===")
    from services.landslide_service import landslide_service
    
    # テスト地点: 山間部
    test_points = [
        (35.7101, 139.5689, "調布市周辺"),
        (35.7796, 139.3994, "青梅市周辺（山間部）"),
        (35.6584, 139.6817, "東京駅付近（平地）"),
    ]
    
    for lat, lng, name in test_points:
        is_risk, risk_type = await landslide_service.check_landslide_risk(lat, lng)
        if is_risk:
            print(f"⚠️ {name}: 土砂災害リスクあり ({risk_type})")
        else:
            print(f"✅ {name}: 土砂災害リスクなし")

async def main():
    print("🔍 ハザードサービス動作確認開始...")
    
    await test_flood_service()
    await test_tsunami_service()
    await test_landslide_service()
    
    print("\n✅ テスト完了")

if __name__ == "__main__":
    asyncio.run(main())
