"""
気象警報サービス (JMA Official JSON版)
気象庁の公式JSONデータを使用して気象警報を取得する
エンドポイント: https://www.jma.go.jp/bosai/warning/data/warning/{pref_code}.json
"""

import httpx
import json
import os
from typing import Optional, Dict
from datetime import datetime, timedelta
from pydantic import BaseModel


class WeatherWarning(BaseModel):
    """気象警報・注意報"""
    type: str  # "大雨警報", "洪水注意報" など
    level: str  # "警報", "注意報", "特別警報"
    areas: list[str] = []  # 対象地域
    issued_at: Optional[str] = None


class WeatherAlerts(BaseModel):
    """気象警報まとめ"""
    warnings: list[WeatherWarning] = []
    has_major_alert: bool = False
    alert_type: Optional[str] = None  # "RAIN" | "FLOOD" | "STORM" | None
    alert_message: Optional[str] = None


class WeatherWarningService:
    """
    気象庁 防災情報 API クライアント (非公式JSON)
    """
    
    BASE_URL = "https://www.jma.go.jp/bosai/warning/data/warning"
    
    # 警報コードマッピング (JMA仕様)
    # https://www.jma.go.jp/bosai/warning/const/warning_code.json より推測
    WARNING_CODES = {
        "03": {"name": "大雨", "level": "警報"},
        "04": {"name": "洪水", "level": "警報"},
        "05": {"name": "暴風", "level": "警報"},
        "06": {"name": "暴風雪", "level": "警報"},
        "07": {"name": "大雪", "level": "警報"},
        "08": {"name": "波浪", "level": "警報"},
        "09": {"name": "高潮", "level": "警報"},
        "33": {"name": "大雨", "level": "特別警報"},
        "35": {"name": "暴風", "level": "特別警報"},
        "36": {"name": "暴風雪", "level": "特別警報"},
        "37": {"name": "大雪", "level": "特別警報"},
        "38": {"name": "波浪", "level": "特別警報"},
        "39": {"name": "高潮", "level": "特別警報"},
        # 注意報
        "10": {"name": "大雨", "level": "注意報"},
        "12": {"name": "大雪", "level": "注意報"},
        "13": {"name": "風雪", "level": "注意報"},
        "14": {"name": "雷", "level": "注意報"},
        "15": {"name": "強風", "level": "注意報"},
        "16": {"name": "波浪", "level": "注意報"},
        "18": {"name": "洪水", "level": "注意報"},
    }
    
    _cache: dict = {}
    _cache_ttl = timedelta(minutes=5)
    _area_map: Dict[str, dict] = {} # "渋谷区" -> {"code": "1311300", "parent": "130000"}
    
    def __init__(self):
        self.client = httpx.AsyncClient(timeout=10.0)
        self._load_area_data()
    
    def _load_area_data(self):
        """area.jsonをロードしてマッピングを作成"""
        try:
            json_path = os.path.join(os.path.dirname(__file__), "../data/area.json")
            if not os.path.exists(json_path):
                print(f"⚠️ area.json not found at {json_path}")
                return
                
            with open(json_path, "r", encoding="utf-8") as f:
                area_data = json.load(f)
            
            # centers (地方) -> children (都道府県) -> children (市区町村)
            centers = area_data.get("centers", {})
            offices = area_data.get("offices", {}) # 都道府県レベル
            class10s = area_data.get("class10s", {}) # 市区町村レベル
            class15s = area_data.get("class15s", {}) # 政令指定都市の区など
            class20s = area_data.get("class20s", {}) # さらに細かい区分
            
            # 都道府県の逆引きマップ (code -> parent code) は area.json からは直接わからないが
            # offices の各コードが都道府県コード (e.g. 130000)
            
            # マッピング作成戦略:
            # class10s, class15s, class20s の name/kana をキーにしてコードと親コードを保存
            
            def register_map(data_dict):
                for code, info in data_dict.items():
                    name = info.get("name", "")
                    parent = info.get("parent", "")
                    if name:
                        self._area_map[name] = {"code": code, "parent": parent}
                        # "渋谷区" -> code
            
            register_map(class10s)
            register_map(class15s)
            register_map(class20s)
            
            # 都道府県コードの解決のため、parentコードから更に辿る必要がある
            # class10s/15s/20s の parent は、offices (都道府県) のコードを指していることが多い
            
            print(f"✅ Loaded {len(self._area_map)} areas from area.json")
            
        except Exception as e:
            print(f"⚠️ Failed to load area.json: {e}")

    async def get_warnings_for_area(self, area_name: str) -> list[WeatherWarning]:
        """指定地域の警報を取得"""
        if not area_name:
            return []
            
        # マッピングからコードを取得
        area_info = self._area_map.get(area_name)
        if not area_info:
            print(f"⚠️ Area code not found for: {area_name}")
            return []
            
        target_code = area_info["code"]
        pref_code = area_info["parent"]
        
        # 親コードが不明、またはJMAのエンドポイント(offices)にない場合の解決が必要だが
        # 基本的に parent は pref_code (130000等) になっているはず
        
        cache_key = f"jma_{pref_code}"
        if self._is_cache_valid(cache_key):
            pref_data = self._cache[cache_key]["data"]
        else:
            pref_data = await self._fetch_jma_warnings(pref_code)
            if pref_data:
                self._set_cache(cache_key, pref_data)
        
        if not pref_data:
            return []
            
        return self._extract_warnings(pref_data, target_code, area_name)

    async def _fetch_jma_warnings(self, pref_code: str) -> Optional[dict]:
        """JMA APIから都道府県ごとのデータを取得"""
        url = f"{self.BASE_URL}/{pref_code}.json"
        try:
            response = await self.client.get(url)
            if response.status_code == 404:
                # 親コードがさらに親（地方など）を指している可能性や、対応しないコードの可能性
                return None
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"⚠️ JMA API Error ({pref_code}): {e}")
            return None

    def _extract_warnings(self, data: dict, area_code: str, area_name: str) -> list[WeatherWarning]:
        """JSONデータから特定エリアの警報を抽出"""
        warnings = []
        try:
            area_types = data.get("areaTypes", [])
            # areaTypes[1] が通常 市区町村ごとのデータ (class10s/15s/20s)
            # 構造を探索して該当コードを探す
            
            target_warnings = []
            
            for area_type in area_types:
                areas = area_type.get("areas", [])
                for area in areas:
                    if area.get("code") == area_code:
                        target_warnings = area.get("warnings", [])
                        break
                if target_warnings:
                    break
            
            for w in target_warnings:
                status = w.get("status")
                # "発表警報・注意報はなし" や "解除" はスキップ
                if status == "発表警報・注意報はなし" or status == "解除":
                    continue
                
                code = w.get("code")
                if code in self.WARNING_CODES:
                    info = self.WARNING_CODES[code]
                    warnings.append(WeatherWarning(
                        type=f"{info['name']}{info['level']}",
                        level=info['level'],
                        areas=[area_name],
                        issued_at=data.get("reportDatetime")
                    ))
                    
        except Exception as e:
            print(f"⚠️ Error parsing JMA data: {e}")
            
        return warnings

    async def get_weather_alerts(self, municipalities: list[str]) -> WeatherAlerts:
        """
        指定市区町村リストの警報を統合取得 (上位互換メソッド)
        """
        all_warnings = []
        for muni in municipalities:
            if not muni: continue
            warnings = await self.get_warnings_for_area(muni)
            all_warnings.extend(warnings)
        
        # 重複除去と重大度判定（既存ロジックと同じ）
        unique_warnings = []
        seen = set()
        for w in all_warnings:
            key = f"{w.type}_{w.level}"
            if key not in seen:
                seen.add(key)
                unique_warnings.append(w)
        
        has_major_alert = False
        alert_type = None
        alert_message = None
        
        for warning in unique_warnings:
            if warning.level in ["特別警報", "警報"]:
                has_major_alert = True
                if "大雨" in warning.type:
                    alert_type = "RAIN"
                    alert_message = "⚠️ 大雨警報が発令されています。"
                elif "洪水" in warning.type:
                    alert_type = "FLOOD"
                    alert_message = "🌊 洪水警報が発令されています。"
                elif "暴風" in warning.type:
                    alert_type = "STORM"
                    alert_message = "💨 暴風警報が発令されています。"
                # 優先度順に上書きしない（最初に見つけた重大警報を優先）
                if alert_type: break
        
        return WeatherAlerts(
            warnings=unique_warnings,
            has_major_alert=has_major_alert,
            alert_type=alert_type,
            alert_message=alert_message
        )

    def _is_cache_valid(self, key: str) -> bool:
        if key not in self._cache: return False
        return datetime.now() - self._cache[key]["time"] < self._cache_ttl
    
    def _set_cache(self, key: str, data):
        self._cache[key] = {"data": data, "time": datetime.now()}

# シングルトン
weather_warning_service = WeatherWarningService()
