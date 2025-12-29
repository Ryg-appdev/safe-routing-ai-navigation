"""
ジオコーディングサービス
座標→市区町村の逆ジオコーディングを行う
"""

import googlemaps
from typing import Optional
from functools import lru_cache
from geopy.distance import geodesic


class GeocodeService:
    """
    Google Maps Geocoding APIを使用した逆ジオコーディング
    """
    
    def __init__(self, client: googlemaps.Client):
        self.client = client
        # メモリキャッシュ（同じ座標の重複リクエストを防ぐ）
        self._cache: dict[str, str] = {}
    
    def get_municipality(self, lat: float, lng: float) -> Optional[str]:
        """
        座標から市区町村名を取得
        :return: "渋谷区", "新宿区" など、または None
        """
        # キャッシュキー（小数点2桁で丸めて近い座標をまとめる）
        cache_key = f"{round(lat, 2)}_{round(lng, 2)}"
        
        if cache_key in self._cache:
            return self._cache[cache_key]
        
        if not self.client:
            print("⚠️ Google Maps Client is not initialized.")
            return None
        
        try:
            results = self.client.reverse_geocode(
                (lat, lng),
                language="ja",
                result_type=["locality", "sublocality", "administrative_area_level_2"]
            )
            
            if not results:
                return None
            
            # 市区町村を抽出
            municipality = None
            prefecture = None
            
            for result in results:
                for component in result.get("address_components", []):
                    types = component.get("types", [])
                    name = component.get("long_name", "")
                    
                    # 市区町村レベル
                    if "locality" in types or "sublocality_level_1" in types:
                        municipality = name
                    # 区（東京23区など）
                    elif "administrative_area_level_2" in types:
                        if municipality is None:
                            municipality = name
                    # 都道府県
                    elif "administrative_area_level_1" in types:
                        prefecture = name
            
            # キャッシュに保存
            self._cache[cache_key] = municipality
            
            return municipality
            
        except Exception as e:
            print(f"⚠️ Geocoding Error: {e}")
            return None
    
    def get_prefecture(self, lat: float, lng: float) -> Optional[str]:
        """
        座標から都道府県名を取得
        """
        if not self.client:
            return None
        
        try:
            results = self.client.reverse_geocode(
                (lat, lng),
                language="ja",
                result_type=["administrative_area_level_1"]
            )
            
            if not results:
                return None
            
            for result in results:
                for component in result.get("address_components", []):
                    if "administrative_area_level_1" in component.get("types", []):
                        return component.get("long_name")
            
            return None
            
        except Exception as e:
            print(f"⚠️ Geocoding Error: {e}")
            return None
    
    def get_municipalities_on_route(self, waypoints: list[dict]) -> list[str]:
        """
        ルート上のウェイポイントから市区町村リストを抽出
        :param waypoints: [{"lat": 35.0, "lng": 139.0}, ...]
        :return: ["渋谷区", "新宿区", ...] (重複なし)
        """
        municipalities = set()
        prefectures = set()
        
        # サンプリング（全ポイントではなく間引いて取得）
        # 50ポイント以上なら10個おきにサンプリング
        step = max(1, len(waypoints) // 10)
        sampled = waypoints[::step]
        
        # 最初と最後は必ず含める
        if waypoints and waypoints[0] not in sampled:
            sampled.insert(0, waypoints[0])
        if waypoints and waypoints[-1] not in sampled:
            sampled.append(waypoints[-1])
        
        for wp in sampled:
            lat = wp.get("lat", 0)
            lng = wp.get("lng", 0)
            
            # 市区町村を取得
            muni = self.get_municipality(lat, lng)
            if muni:
                municipalities.add(muni)
            
            # 都道府県も取得
            pref = self.get_prefecture(lat, lng)
            if pref:
                prefectures.add(pref)
        
        # 都道府県も含めて返す（警報は都道府県単位のこともあるため）
        return list(municipalities) + list(prefectures)

    def get_municipality_from_address(self, address: str) -> Optional[str]:
        """
        住所・地名文字列から市区町村名を取得 (Geocoding)
        :param address: "渋谷駅", "東京タワー" 等
        :return: "渋谷区", "港区" 等
        """
        if not address:
            return None
            
        # キャッシュ確認
        cache_key = f"geo_{address}"
        if cache_key in self._cache:
            return self._cache[cache_key]

        if not self.client:
            return None
            
        try:
            # Geocoding API 呼び出し
            results = self.client.geocode(
                address,
                language="ja"
            )
            
            if not results:
                print(f"⚠️ Geo lookup failed for: {address}")
                return None
            
            # 結果から市区町村を抽出
            municipality = None
            
            # 最初の結果を使用
            result = results[0]
            for component in result.get("address_components", []):
                types = component.get("types", [])
                name = component.get("long_name", "")
                
                # 政令指定都市の区 (ward)
                if "administrative_area_level_2" in types and "political" in types:
                    # 東京都23区も administrative_area_level_2 + locality の場合があるが
                    # 23区は locality であることが多い。
                    # Google Maps APIの仕様上、Wardは level_2 に来ることが多い
                    if municipality is None:
                        municipality = name
                        
                # 市町村 (locality)
                elif "locality" in types and "political" in types:
                     municipality = name
            
            # 見つからない場合、result全体から探す（簡易）
            if not municipality:
                 # 住所文字列から推測するのは危険なのでやめる
                 pass

            if municipality:
                self._cache[cache_key] = municipality
                return municipality
            else:
                print(f"⚠️ No municipality found in geo result for: {address}")
                return None

        except Exception as e:
            print(f"⚠️ Geocoding API Error: {e}")
            return None

    def get_poi_name(self, lat: float, lng: float) -> Optional[dict]:
        """
        座標周辺の施設名と正確な位置を取得 (Geocoding API)
        :param lat: 緯度
        :param lng: 経度
        :return: {"name": "セブンイレブン", "lat": 35..., "lng": 139...} など
        """
        if not self.client:
            return None
            
        cache_key = f"poi_{round(lat, 4)}_{round(lng, 4)}"
        if cache_key in self._cache:
            return self._cache[cache_key]
            
        try:
            # Places API (Legacy) が無効化されている可能性があるため、
            # Geocoding APIのreverse_geocodeを使用する（こちらは有効であることが確認済み）
            results = self.client.reverse_geocode(
                (lat, lng),
                language='ja'
                # result_typeを指定しないことで、最も詳細な住所/POIを取得する
            )
            
            if not results:
                return None
                
            candidates = []
            
            for result in results:
                types = result.get('types', [])
                
                # 距離計算
                loc = result['geometry']['location']
                dist = geodesic((lat, lng), (loc['lat'], loc['lng'])).meters
                
                # スコアリング (優先度判定)
                score = 0
                max_dist = 100.0
                
                # 交通機関 (最優先) -> 距離制限を大幅緩和 (駅は広いので300mまで許容)
                if any(t in types for t in ['train_station', 'subway_station', 'light_rail_station', 'transit_station']):
                    score = 100
                    max_dist = 300.0
                # 観光地・公共施設・商業施設 (高)
                elif any(t in types for t in ['tourist_attraction', 'museum', 'park', 'amusement_park', 'shopping_mall', 'department_store', 'school', 'hospital']):
                    score = 80
                    max_dist = 150.0
                # 一般的なPOI (中)
                elif 'point_of_interest' in types or 'establishment' in types:
                    score = 50
                # 建物名 (低)
                elif 'premise' in types:
                    score = 10
                else:
                    # それ以外は対象外
                    continue
                
                # 距離チェック (タイプごとの許容範囲で判定)
                if dist > max_dist:
                    print(f"🚫 Rejected: {result.get('address_components', [{}])[0].get('long_name')} (Dist: {dist:.1f}m > {max_dist}m, Score: {score})")
                    continue
                    
                candidates.append({
                    "score": score,
                    "dist": dist,
                    "data": result
                })
            
            if not candidates:
                return None
                
            # 優先順位付き選択ロジック
            best = None
            
            # 1. 至近距離(40m以内)に重要な施設(Score >= 50)があるか？ -> あればそれを優先 (コンビニなど)
            # 例: 駅が遠くても、目の前のコンビニをタップした場合はコンビニを返す
            nearby_high = [c for c in candidates if c['score'] >= 50 and c['dist'] <= 40.0]
            if nearby_high:
                # スコア高い順 -> 近い順
                nearby_high.sort(key=lambda x: (-x['score'], x['dist']))
                best = nearby_high[0]
                print(f"🎯 Step 1 (Nearby High-Value): {best['data'].get('address_components', [{}])[0].get('long_name')} ({best['dist']:.1f}m)")
            
            # 2. なければ、範囲内(300m)にある「駅」(Score 100) を探す -> 文字タップ救済
            # 例: 目の前がマンション(Score 10)でも、少し離れた駅の文字をタップしたとみなす
            if not best:
                stations = [c for c in candidates if c['score'] == 100]
                if stations:
                    stations.sort(key=lambda x: x['dist']) # 一番近い駅
                    best = stations[0]
                    print(f"🎯 Step 2 (Station Snap): {best['data'].get('address_components', [{}])[0].get('long_name')} ({best['dist']:.1f}m)")
            
            # 3. それもなければ、全体の中からベストを選ぶ (マンション名など)
            if not best:
                candidates.sort(key=lambda x: (-x['score'], x['dist']))
                best = candidates[0]
                print(f"🎯 Step 3 (Fallback): {best['data'].get('address_components', [{}])[0].get('long_name')} ({best['dist']:.1f}m)")
            
            result = best['data']
            if result.get('address_components'):
                name = result['address_components'][0]['long_name']
                loc = result['geometry']['location']
                
                poi_data = {
                    "name": name,
                    "lat": loc['lat'],
                    "lng": loc['lng']
                }
                self._cache[cache_key] = poi_data
                return poi_data
            
            return None
            
        except Exception as e:
            print(f"⚠️ Geocoding API Service Error: {e}")
            return None
