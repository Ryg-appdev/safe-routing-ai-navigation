"""
避難所検索サービス
国土地理院「指定緊急避難場所」データを使用
https://www.gsi.go.jp/bousaichiri/hinanbasho.html
"""

import json
import math
import os
import requests
from typing import List, Dict, Any, Optional
from pathlib import Path


# 災害種別フラグのマッピング（GeoJSONフィールド名 → API災害タイプ）
DISASTER_TYPE_MAPPING = {
    "洪水": "洪水",
    "崖崩れ、土石流及び地滑り": "崖崩れ、土石流及び地滑り",
    "高潮": "高潮",
    "地震": "地震",
    "津波": "津波",
    "大規模な火事": "大規模な火事",
    "内水氾濫": "内水氾濫",
    "火山現象": "火山現象",
}


class ShelterService:
    """
    避難所検索サービス
    データソース: 国土地理院「指定緊急避難場所」GeoJSON
    """
    
    # 国土地理院GeoJSONのURL（全国一括・指定緊急避難場所）
    GSI_GEOJSON_URL = "https://hinanmap.gsi.go.jp/hinanjocp/defaultFtpData/geoJSON/mergeFromCity_2.geojson"
    
    def __init__(self):
        """初期化: GeoJSONデータを読み込み"""
        self.shelters: List[Dict[str, Any]] = []
        self.data_path = Path(__file__).parent.parent / "data" / "emergency_shelters.geojson"
        self._load_data()
    
    def _download_data(self) -> bool:
        """国土地理院からGeoJSONをダウンロード"""
        print("🏫 [ShelterService] Downloading shelter data from GSI...", flush=True)
        try:
            resp = requests.get(self.GSI_GEOJSON_URL, timeout=60)
            if resp.status_code == 200:
                # ディレクトリ作成
                self.data_path.parent.mkdir(parents=True, exist_ok=True)
                # ファイル保存
                with open(self.data_path, "w", encoding="utf-8") as f:
                    f.write(resp.text)
                print(f"🏫 [ShelterService] Downloaded and saved to {self.data_path}", flush=True)
                return True
            else:
                print(f"⚠️ [ShelterService] Download failed: {resp.status_code}", flush=True)
                return False
        except Exception as e:
            print(f"⚠️ [ShelterService] Download error: {e}", flush=True)
            return False
    
    def _load_data(self) -> None:
        """GeoJSONデータを読み込み（なければダウンロード）"""
        # キャッシュファイルがなければダウンロード
        if not self.data_path.exists():
            if not self._download_data():
                print("⚠️ [ShelterService] No shelter data available", flush=True)
                return
        
        try:
            with open(self.data_path, "r", encoding="utf-8") as f:
                geojson = json.load(f)
            
            # GeoJSONからデータを抽出
            for feature in geojson.get("features", []):
                props = feature.get("properties", {})
                coords = feature.get("geometry", {}).get("coordinates", [])
                
                if len(coords) >= 2:
                    # 災害種別フラグを抽出
                    disaster_flags = {}
                    for key in DISASTER_TYPE_MAPPING.keys():
                        # フラグが"1"または1の場合に対応
                        flag_value = props.get(key, "0")
                        disaster_flags[key] = str(flag_value) == "1"
                    
                    self.shelters.append({
                        "name": props.get("施設・場所名", props.get("name", "不明")),
                        "address": props.get("住所", props.get("address", "")),
                        "type": "指定緊急避難場所",
                        "lat": float(coords[1]) if isinstance(coords[1], (int, float, str)) else 0,
                        "lng": float(coords[0]) if isinstance(coords[0], (int, float, str)) else 0,
                        "disaster_flags": disaster_flags,
                    })
            
            print(f"🏫 [ShelterService] Loaded {len(self.shelters)} emergency shelters", flush=True)
            
        except Exception as e:
            print(f"⚠️ [ShelterService] Load error: {e}", flush=True)
    
    def _haversine_distance(self, lat1: float, lng1: float, lat2: float, lng2: float) -> float:
        """2点間の距離をハバーサイン公式で計算（メートル単位）"""
        R = 6371000  # 地球の半径（メートル）
        
        phi1 = math.radians(lat1)
        phi2 = math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lng2 - lng1)
        
        a = math.sin(delta_phi / 2) ** 2 + \
            math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        
        return R * c
    
    def find_nearest(
        self, 
        lat: float, 
        lng: float, 
        disaster_type: Optional[str] = None,
        limit: int = 3
    ) -> List[Dict[str, Any]]:
        """
        最寄りの避難所を検索
        
        Args:
            lat: 緯度
            lng: 経度
            disaster_type: 災害種別（"洪水", "津波", "高潮" など）
            limit: 返却件数
        
        Returns:
            避難所リスト（距離順）
        """
        if not self.shelters:
            print("⚠️ [ShelterService] No shelter data loaded", flush=True)
            return []
        
        # 災害種別でフィルタリング
        candidates = self.shelters
        if disaster_type and disaster_type in DISASTER_TYPE_MAPPING:
            candidates = [
                s for s in self.shelters 
                if s["disaster_flags"].get(disaster_type, False)
            ]
            print(f"🏫 [ShelterService] Filtered by '{disaster_type}': {len(candidates)} shelters", flush=True)
        
        if not candidates:
            # フィルタ結果が0件の場合、全避難場所から検索
            print(f"⚠️ [ShelterService] No shelters for '{disaster_type}', using all", flush=True)
            candidates = self.shelters
        
        # 距離を計算してソート
        shelters_with_distance = []
        for shelter in candidates:
            distance = self._haversine_distance(lat, lng, shelter["lat"], shelter["lng"])
            shelters_with_distance.append({
                "name": shelter["name"],
                "address": shelter["address"],
                "type": shelter["type"],
                "lat": shelter["lat"],
                "lng": shelter["lng"],
                "distance": round(distance),
            })
        
        # 距離順でソート
        shelters_with_distance.sort(key=lambda x: x["distance"])
        
        result = shelters_with_distance[:limit]
        if result:
            print(f"🏫 [ShelterService] Nearest: {result[0]['name']} ({result[0]['distance']}m)", flush=True)
        
        return result


# シングルトンインスタンス
_shelter_service: Optional[ShelterService] = None


def get_shelter_service() -> ShelterService:
    """ShelterServiceのシングルトンインスタンスを取得"""
    global _shelter_service
    if _shelter_service is None:
        _shelter_service = ShelterService()
    return _shelter_service
