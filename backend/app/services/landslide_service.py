"""
土砂災害ハザードマップサービス
国土地理院 地理院タイルを使用して土砂災害警戒区域を判定する
https://disaportaldata.gsi.go.jp/
"""

import httpx
import math
from typing import Optional, Tuple
from PIL import Image
from io import BytesIO


class LandslideService:
    """
    国土地理院 土砂災害ハザードマップ タイル解析
    
    タイルURL形式:
    - 急傾斜地崩壊: https://disaportaldata.gsi.go.jp/raster/05_doshasakaiarea_1/{z}/{x}/{y}.png
    - 土石流: https://disaportaldata.gsi.go.jp/raster/05_doshasakaiarea_2/{z}/{x}/{y}.png  
    - 地すべり: https://disaportaldata.gsi.go.jp/raster/05_doshasakaiarea_3/{z}/{x}/{y}.png
    """
    
    BASE_URL = "https://disaportaldata.gsi.go.jp/raster"
    
    HAZARD_TYPES = {
        1: "急傾斜地崩壊",
        2: "土石流",
        3: "地すべり",
    }
    
    # 警戒区域の色判定（赤系・黄系ピクセル）
    # 警戒区域（イエローゾーン）: 黄色系
    # 特別警戒区域（レッドゾーン）: 赤色系
    
    def __init__(self):
        self.client = httpx.AsyncClient(timeout=10.0)
        self._cache: dict[str, bool] = {}
    
    async def check_landslide_risk(
        self, 
        lat: float, 
        lng: float, 
        zoom: int = 15
    ) -> Tuple[bool, Optional[str]]:
        """
        指定座標が土砂災害警戒区域内かチェック
        :return: (is_risk, risk_type)
        """
        cache_key = f"{round(lat, 4)}_{round(lng, 4)}"
        if cache_key in self._cache:
            return self._cache[cache_key]
        
        # 各ハザードタイプをチェック
        for hazard_id, hazard_name in self.HAZARD_TYPES.items():
            is_hazard = await self._check_tile(lat, lng, hazard_id, zoom)
            if is_hazard:
                result = (True, hazard_name)
                self._cache[cache_key] = result
                return result
        
        result = (False, None)
        self._cache[cache_key] = result
        return result
    
    async def _check_tile(
        self, 
        lat: float, 
        lng: float, 
        hazard_type: int,
        zoom: int
    ) -> bool:
        """タイルを取得してピクセル色を判定"""
        try:
            # 座標からタイル座標を計算
            tile_x, tile_y, pixel_x, pixel_y = self._latlng_to_tile(lat, lng, zoom)
            
            # タイル取得
            url = f"{self.BASE_URL}/05_doshasakaiarea_{hazard_type}/{zoom}/{tile_x}/{tile_y}.png"
            response = await self.client.get(url)
            
            if response.status_code == 404:
                # タイルなし = その地域にはデータなし
                return False
            
            response.raise_for_status()
            
            # 画像解析
            image = Image.open(BytesIO(response.content))
            image = image.convert("RGBA")
            
            # 指定ピクセルの色を取得
            try:
                r, g, b, a = image.getpixel((pixel_x, pixel_y))
            except IndexError:
                return False
            
            # 透明ピクセルは対象外
            if a < 100:
                return False
            
            # 警戒区域判定（赤系・黄系の色）
            # レッドゾーン: 赤が強い
            if r > 150 and g < 100 and b < 100:
                return True
            
            # イエローゾーン: 黄が強い
            if r > 150 and g > 150 and b < 100:
                return True
            
            return False
            
        except Exception as e:
            print(f"⚠️ 土砂災害タイル取得エラー: {e}")
            return False
    
    def _latlng_to_tile(
        self, 
        lat: float, 
        lng: float, 
        zoom: int
    ) -> Tuple[int, int, int, int]:
        """
        緯度経度からタイル座標とピクセル位置を計算
        :return: (tile_x, tile_y, pixel_x, pixel_y)
        """
        n = 2 ** zoom
        
        # タイル座標
        tile_x = int((lng + 180.0) / 360.0 * n)
        lat_rad = math.radians(lat)
        tile_y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
        
        # タイル内のピクセル位置（256x256タイル）
        pixel_x = int(((lng + 180.0) / 360.0 * n - tile_x) * 256)
        pixel_y = int(((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n - tile_y) * 256)
        
        # 範囲制限
        pixel_x = max(0, min(255, pixel_x))
        pixel_y = max(0, min(255, pixel_y))
        
        return tile_x, tile_y, pixel_x, pixel_y
    
    async def scan_route_for_landslide(
        self, 
        waypoints: list[dict],
        sample_step: int = 5
    ) -> list[dict]:
        """
        ルート上の土砂災害リスクをスキャン
        :return: [{"lat": ..., "lng": ..., "risk_type": ...}, ...]
        """
        risks = []
        
        # サンプリング（全点ではなく間引き）
        sampled = waypoints[::sample_step]
        
        for wp in sampled:
            lat = wp.get("lat", 0)
            lng = wp.get("lng", 0)
            
            is_risk, risk_type = await self.check_landslide_risk(lat, lng)
            if is_risk:
                risks.append({
                    "lat": lat,
                    "lng": lng,
                    "risk_type": risk_type
                })
        
        return risks


# シングルトンインスタンス
landslide_service = LandslideService()
