"""
地震・津波情報サービス
P2P地震情報 API v2 を使用してリアルタイムの地震・津波情報を取得する
https://www.p2pquake.net/develop/json_api_v2/
"""

import httpx
from typing import Optional
from datetime import datetime, timedelta
from pydantic import BaseModel
import asyncio


# === データモデル ===

class EarthquakeInfo(BaseModel):
    """地震情報"""
    id: str
    time: str  # 発生時刻
    magnitude: Optional[float] = None
    max_intensity: Optional[str] = None  # 最大震度
    epicenter: Optional[str] = None  # 震源地
    depth: Optional[int] = None  # 深さ (km)
    areas: list[str] = []  # 震度観測地域


class TsunamiWarning(BaseModel):
    """津波警報・注意報"""
    id: str
    time: str
    grade: str  # "MajorWarning" | "Warning" | "Watch" | "None"
    areas: list[str] = []  # 対象地域


class DisasterAlerts(BaseModel):
    """災害警報まとめ"""
    earthquakes: list[EarthquakeInfo] = []
    tsunamis: list[TsunamiWarning] = []
    has_major_alert: bool = False  # 重大警報があるか
    alert_type: Optional[str] = None  # "TSUNAMI" | "EARTHQUAKE" | None
    alert_message: Optional[str] = None  # 表示用メッセージ


# === サービスクラス ===

class EarthquakeService:
    """
    P2P地震情報 API クライアント
    - 地震情報: /jma/quake
    - 津波予報: /jma/tsunami
    - 緊急地震速報: /history?codes=556
    """
    
    BASE_URL = "https://api.p2pquake.net/v2"
    
    # キャッシュ（レート制限対策）
    _cache: dict = {}
    _cache_ttl = timedelta(seconds=30)
    
    def __init__(self):
        self.client = httpx.AsyncClient(timeout=10.0)
    
    async def get_recent_earthquakes(self, limit: int = 5) -> list[EarthquakeInfo]:
        """
        直近の地震情報を取得
        """
        cache_key = "earthquakes"
        if self._is_cache_valid(cache_key):
            return self._cache[cache_key]["data"]
        
        try:
            response = await self.client.get(
                f"{self.BASE_URL}/jma/quake",
                params={"limit": limit}
            )
            response.raise_for_status()
            data = response.json()
            
            earthquakes = []
            for item in data:
                eq = self._parse_earthquake(item)
                if eq:
                    earthquakes.append(eq)
            
            self._set_cache(cache_key, earthquakes)
            return earthquakes
            
        except Exception as e:
            print(f"⚠️ 地震情報取得エラー: {e}")
            return []
    
    async def get_tsunami_warnings(self) -> list[TsunamiWarning]:
        """
        津波警報・注意報を取得
        """
        cache_key = "tsunamis"
        if self._is_cache_valid(cache_key):
            return self._cache[cache_key]["data"]
        
        try:
            response = await self.client.get(
                f"{self.BASE_URL}/jma/tsunami",
                params={"limit": 3}
            )
            response.raise_for_status()
            data = response.json()
            
            tsunamis = []
            for item in data:
                tw = self._parse_tsunami(item)
                if tw and tw.grade != "None":
                    tsunamis.append(tw)
            
            self._set_cache(cache_key, tsunamis)
            return tsunamis
            
        except Exception as e:
            print(f"⚠️ 津波情報取得エラー: {e}")
            return []
    
    async def get_disaster_alerts(self, target_areas: list[str] = None) -> DisasterAlerts:
        """
        災害警報の総合情報を取得
        target_areas: 対象地域リスト（例: ["東京都", "渋谷区"]）
        """
        # 並列で取得
        earthquakes, tsunamis = await asyncio.gather(
            self.get_recent_earthquakes(limit=3),
            self.get_tsunami_warnings()
        )
        
        # 対象地域でフィルタリング（指定があれば）
        if target_areas:
            # 地震: 震度観測地域に含まれているか
            earthquakes = [
                eq for eq in earthquakes
                if any(area in eq.areas or area in (eq.epicenter or "") for area in target_areas)
            ]
            # 津波: 対象地域に含まれているか
            tsunamis = [
                tw for tw in tsunamis
                if any(area in tw.areas for area in target_areas)
            ]
        
        # 重大警報の判定
        has_major_alert = False
        alert_type = None
        alert_message = None
        
        # 津波警報チェック（最優先）
        major_tsunami = next((tw for tw in tsunamis if tw.grade in ["MajorWarning", "Warning"]), None)
        if major_tsunami:
            has_major_alert = True
            alert_type = "TSUNAMI"
            if major_tsunami.grade == "MajorWarning":
                alert_message = "🔴 大津波警報が発令されています。直ちに高台へ避難してください。"
            else:
                alert_message = "⚠️ 津波警報が発令されています。海岸から離れてください。"
        
        # 大きな地震チェック
        elif earthquakes:
            # 震度5弱以上をチェック
            major_eq = next(
                (eq for eq in earthquakes if self._intensity_to_int(eq.max_intensity) >= 5),
                None
            )
            if major_eq:
                has_major_alert = True
                alert_type = "EARTHQUAKE"
                alert_message = f"⚠️ {major_eq.epicenter or '震源不明'}で震度{major_eq.max_intensity}の地震が発生しました。"
        
        return DisasterAlerts(
            earthquakes=earthquakes,
            tsunamis=tsunamis,
            has_major_alert=has_major_alert,
            alert_type=alert_type,
            alert_message=alert_message
        )
    
    # === 内部メソッド ===
    
    def _parse_earthquake(self, data: dict) -> Optional[EarthquakeInfo]:
        """APIレスポンスをパース"""
        try:
            earthquake = data.get("earthquake", {})
            points = data.get("points", [])
            
            # 震度観測地域を抽出
            areas = []
            for point in points:
                pref = point.get("pref", "")
                addr = point.get("addr", "")
                if pref and pref not in areas:
                    areas.append(pref)
            
            return EarthquakeInfo(
                id=data.get("id", ""),
                time=earthquake.get("time", ""),
                magnitude=earthquake.get("magnitude"),
                max_intensity=self._convert_intensity(data.get("earthquake", {}).get("maxScale")),
                epicenter=earthquake.get("hypocenter", {}).get("name"),
                depth=earthquake.get("hypocenter", {}).get("depth"),
                areas=areas
            )
        except Exception as e:
            print(f"地震情報パースエラー: {e}")
            return None
    
    def _parse_tsunami(self, data: dict) -> Optional[TsunamiWarning]:
        """津波情報をパース"""
        try:
            areas = []
            grade = "None"
            
            for area in data.get("areas", []):
                name = area.get("name", "")
                if name:
                    areas.append(name)
                area_grade = area.get("grade", "")
                # 最も深刻なグレードを採用
                if area_grade == "MajorWarning":
                    grade = "MajorWarning"
                elif area_grade == "Warning" and grade != "MajorWarning":
                    grade = "Warning"
                elif area_grade == "Watch" and grade not in ["MajorWarning", "Warning"]:
                    grade = "Watch"
            
            return TsunamiWarning(
                id=data.get("id", ""),
                time=data.get("time", ""),
                grade=grade,
                areas=areas
            )
        except Exception as e:
            print(f"津波情報パースエラー: {e}")
            return None
    
    def _convert_intensity(self, scale: int) -> Optional[str]:
        """震度スケール変換（P2P地震情報形式 → 日本式表記）"""
        scale_map = {
            10: "1", 20: "2", 30: "3", 40: "4",
            45: "5弱", 50: "5強",
            55: "6弱", 60: "6強",
            70: "7"
        }
        return scale_map.get(scale)
    
    def _intensity_to_int(self, intensity: Optional[str]) -> int:
        """震度文字列を数値に変換（比較用）"""
        if not intensity:
            return 0
        intensity_map = {
            "1": 1, "2": 2, "3": 3, "4": 4,
            "5弱": 5, "5強": 6,
            "6弱": 7, "6強": 8,
            "7": 9
        }
        return intensity_map.get(intensity, 0)
    
    def _is_cache_valid(self, key: str) -> bool:
        """キャッシュが有効かチェック"""
        if key not in self._cache:
            return False
        return datetime.now() - self._cache[key]["time"] < self._cache_ttl
    
    def _set_cache(self, key: str, data):
        """キャッシュを設定"""
        self._cache[key] = {
            "data": data,
            "time": datetime.now()
        }


# シングルトンインスタンス
earthquake_service = EarthquakeService()
