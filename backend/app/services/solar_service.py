import requests
import os
from typing import Optional, Dict, Any

class SolarService:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://solar.googleapis.com/v1/buildingInsights:findClosest"

    def get_building_insights(self, lat: float, lng: float) -> Optional[Dict[str, Any]]:
        """
        指定座標に最も近い建物のSolarデータを取得する
        """
        params = {
            "location.latitude": lat,
            "location.longitude": lng,
            "requiredQuality": "HIGH",
            "key": self.api_key
        }
        
        try:
            resp = requests.get(self.base_url, params=params, timeout=3.0)
            if resp.status_code == 200:
                return resp.json()
            elif resp.status_code == 404:
                # 近くにデータ対象の建物がない（田舎や海上、データ範囲外）
                return None
            else:
                print(f"⚠️ Solar API Error {resp.status_code}: {resp.text}")
                return None
        except Exception as e:
            print(f"⚠️ Solar API Request Failed: {e}")
            return None

    def evaluate_darkness_risk(self, lat: float, lng: float) -> tuple[float, str]:
        """
        Solar APIの結果を用いて「暗がり/死角リスク」を判定する
        簡易ロジック:
        - 建物データが取得できる -> 建物が密集している -> 死角が多い可能性がある (Urban Shadow)
        - 建物データがない -> 開けている (Open Area)
        
        ※本来はデータレイヤーAPIで日射量を計算するが、Hackathon用に「建物近接＝リスク」と簡易化するか、
        逆に「建物がない＝街灯もなくて暗い」とするか。
        
        ここでは「日常モード(Normal)」では「明るい大通り(建物あり)がいい」とし、
        「非常時」は「建物崩壊リスク」として避ける、などの使い分けができるが、
        一旦「建物がある＝Shadow Risk」としてスコアを少し下げる（要調整）。
        """
        data = self.get_building_insights(lat, lng)
        
        if data:
            # 建物がある
            # name = data.get("name", "Building")
            return (5.0, "建物による死角・日陰")
        else:
            # 建物がない（Open Area）
            return (0.0, "Open Area")
