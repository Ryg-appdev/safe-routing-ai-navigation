"""
津波浸水想定区域ハザードマップサービス
国土地理院 地理院タイルを使用して津波浸水想定区域を判定する
https://disaportaldata.gsi.go.jp/

タイルURL:
- 津波浸水想定区域（想定最大規模）:
  https://disaportaldata.gsi.go.jp/raster/04_tsunami_l2_shinsuishin_data/{z}/{x}/{y}.png

浸水深の色判定:
- 0.3m未満: 薄い黄色
- 0.3m〜1m: 黄色
- 1m〜2m: オレンジ
- 2m〜5m: 赤
- 5m〜10m: 濃い赤
- 10m以上: 紫
"""

import httpx
import math
from typing import Optional, Tuple
from PIL import Image
from io import BytesIO


class TsunamiService:
    """
    国土地理院 津波浸水想定区域 タイル解析
    
    津波による浸水深に応じた色で塗られたタイルを解析し、
    指定座標の津波リスクを判定する
    """
    
    BASE_URL = "https://disaportaldata.gsi.go.jp/raster"
    TILE_PATH = "04_tsunami_l2_shinsuishin_data"
    
    def __init__(self):
        self.client = httpx.AsyncClient(timeout=10.0)
        self._cache: dict[str, Tuple[bool, Optional[str]]] = {}
    
    async def check_tsunami_risk(
        self, 
        lat: float, 
        lng: float, 
        zoom: int = 15
    ) -> Tuple[bool, Optional[str]]:
        """
        指定座標が津波浸水想定区域内かチェック
        :return: (is_risk, depth_category)
        """
        cache_key = f"{round(lat, 4)}_{round(lng, 4)}"
        if cache_key in self._cache:
            return self._cache[cache_key]
        
        result = await self._check_tile(lat, lng, zoom)
        self._cache[cache_key] = result
        return result
    
    async def _check_tile(
        self, 
        lat: float, 
        lng: float, 
        zoom: int
    ) -> Tuple[bool, Optional[str]]:
        """タイルを取得してピクセル色から浸水深を判定"""
        try:
            # 座標からタイル座標を計算
            tile_x, tile_y, pixel_x, pixel_y = self._latlng_to_tile(lat, lng, zoom)
            
            # タイル取得
            url = f"{self.BASE_URL}/{self.TILE_PATH}/{zoom}/{tile_x}/{tile_y}.png"
            response = await self.client.get(url)
            
            if response.status_code == 404:
                # タイルなし = その地域にはデータなし（津波リスクなし）
                return (False, None)
            
            response.raise_for_status()
            
            # 画像解析
            image = Image.open(BytesIO(response.content))
            image = image.convert("RGBA")
            
            # 指定ピクセルの色を取得
            try:
                r, g, b, a = image.getpixel((pixel_x, pixel_y))
            except IndexError:
                return (False, None)
            
            # 透明ピクセルは浸水区域外
            if a < 100:
                return (False, None)
            
            # 浸水深判定（色から推定）
            depth = self._estimate_depth_from_color(r, g, b)
            if depth:
                return (True, depth)
            
            return (False, None)
            
        except Exception as e:
            print(f"⚠️ 津波タイル取得エラー: {e}")
            return (False, None)
    
    def _estimate_depth_from_color(self, r: int, g: int, b: int) -> Optional[str]:
        """
        ピクセル色から津波浸水深カテゴリを推定
        """
        # 紫系（10m以上）
        if 100 <= r <= 180 and g < 80 and b > 100:
            return "10m以上"
        
        # 濃い赤（5m〜10m）
        if r > 180 and g < 80 and b < 80:
            return "5m〜10m"
        
        # 赤（2m〜5m）
        if r > 200 and 50 <= g <= 100 and b < 80:
            return "2m〜5m"
        
        # オレンジ（1m〜2m）
        if r > 200 and 100 <= g <= 180 and b < 100:
            return "1m〜2m"
        
        # 黄（0.3m〜1m）
        if r > 200 and g > 180 and b < 150:
            return "0.3m〜1m"
        
        # 薄い黄（0.3m未満）
        if r > 220 and g > 200:
            return "0.3m未満"
        
        # 判定不能だが色がついている = 何らかのリスクあり
        if r > 150 or g > 150:
            return "0.3m未満"
        
        return None
    
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
    
    async def scan_route_for_tsunami(
        self, 
        waypoints: list[dict],
        sample_step: int = 5
    ) -> list[dict]:
        """
        ルート上の津波リスクをスキャン
        :return: [{"lat": ..., "lng": ..., "depth": ...}, ...]
        """
        risks = []
        
        # サンプリング（全点ではなく間引き）
        sampled = waypoints[::sample_step]
        
        for wp in sampled:
            lat = wp.get("lat", 0)
            lng = wp.get("lng", 0)
            
            is_risk, depth = await self.check_tsunami_risk(lat, lng)
            if is_risk:
                risks.append({
                    "lat": lat,
                    "lng": lng,
                    "depth": depth
                })
        
        return risks


# シングルトンインスタンス
tsunami_service = TsunamiService()
