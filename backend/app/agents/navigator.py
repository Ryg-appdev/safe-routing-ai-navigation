from typing import Dict, Any, List
from google import genai
from google.genai import types
from google.genai import types
import json
import asyncio
import os

# TODO: 実際のAPIクライアントをimportする
# from ..services.routes_service import RoutesService
# from ..services.solar_service import SolarService
# from ..services.places_service import PlacesService

class NavigatorAgent:
    """
    The Navigator (Tool User)
    役割: 外部APIを駆使して、実際のルート探索と物理的リスク評価を行う。
    モデル: Gemini 3 Flash (高速性重視)
    """

    # Sampling Interval
    SAMPLING_INTERVAL_METERS = 100.0
    
    # 警報種別とハザードサービスのマッピング
    ALERT_TO_HAZARD = {
        "大雨警報": "flood",
        "洪水警報": "flood",
        "津波警報": "tsunami",
        "津波注意報": "tsunami",
        "土砂災害警戒情報": "landslide",
    }

    def __init__(self, client: genai.Client):
        self.client = client
        self.model_name = "gemini-3-flash-preview"
        self.tools = []
        self.elevation_service = None
        # アクティブな警報一覧（ハザードチェックの条件に使用）
        self.active_alerts: List[str] = []


        # Initialize Google Maps Client
        api_key = os.environ.get("GOOGLE_MAPS_API_KEY")
        if not api_key:
            print("WARNING: GOOGLE_MAPS_API_KEY not found.")
            self.gmaps = None
        else:
            import googlemaps
            self.gmaps = googlemaps.Client(key=api_key)
            
            # Initialize Services
            try:
                from services.elevation_service import ElevationService
                self.elevation_service = ElevationService(self.gmaps)
            except Exception as e:
                print(f"⚠️ Failed to init ElevationService: {e}")
                
            # Initialize Analyst (Visual Vibe Check)
            try:
                from agents.analyst import AnalystAgent
                self.analyst = AnalystAgent(self.client)
            except Exception as e:
                print(f"⚠️ Failed to init AnalystAgent: {e}")
                self.analyst = None

            # Initialize Solar Service
            try:
                from services.solar_service import SolarService
                self.solar_service = SolarService(api_key)
            except Exception as e:
                print(f"⚠️ Failed to init SolarService: {e}")
                self.solar_service = None

            # Initialize Places Service
            try:
                from services.places_service import PlacesService
                self.places_service = PlacesService(api_key)
            except Exception as e:
                print(f"⚠️ Failed to init PlacesService: {e}")
                self.places_service = None

            # Initialize Hazard Services (Flood, Tsunami, Landslide)
            try:
                from services.flood_service import flood_service
                self.flood_service = flood_service
            except Exception as e:
                print(f"⚠️ Failed to init FloodService: {e}")
                self.flood_service = None
            
            try:
                from services.tsunami_service import tsunami_service
                self.tsunami_service = tsunami_service
            except Exception as e:
                print(f"⚠️ Failed to init TsunamiService: {e}")
                self.tsunami_service = None
            
            try:
                from services.landslide_service import landslide_service
                self.landslide_service = landslide_service
            except Exception as e:
                print(f"⚠️ Failed to init LandslideService: {e}")
                self.landslide_service = None

    async def find_safest_route(self, origin: str, destination: str, risk_preferences: List[str]) -> Dict[str, Any]:
        """
        出発地と目的地から、リスクを考慮した最適ルートを探索する
        """
        print(f"🗺️ [Navigator] Finding route from {origin} to {destination}...", flush=True)

        if not self.gmaps:
            return {"error": "Google Maps API Key missing"}

        # 1. Routes API (Directions) Call
        routes = self.fetch_routes(origin, destination)
        if "error" in routes:
            return routes
        
        directions_result = routes["routes"]
        if not directions_result:
            return {"error": "No route found"}

        # 2. Evaluate Each Route
        evaluated_routes = []
        
        for route in directions_result:
            result = await self.analyze_single_route(route)
            if result:
                evaluated_routes.append(result)

        if not evaluated_routes:
            return {"error": "No valid routes after analysis"}

        # 3. Select Best Route (Highest Score)
        evaluated_routes.sort(key=lambda x: x["score"], reverse=True)
        best_route = evaluated_routes[0]

        return {
            "route_id": "real_route_v1",
            "waypoints": best_route["risk_analysis"].get("details", []), # リスク詳細点
            "best_route_encoding": best_route["overview_polyline"]["points"],
            "risk_assessment": {
                "score": best_route["score"],
                "safety_factors": [f"Route evaluated by {int(self.SAMPLING_INTERVAL_METERS)}m bottleneck logic"],
                "remaining_risks": [d for d in best_route["risk_analysis"]["details"] if d["score"] < 50]
            }
        }
    
    def fetch_routes(self, origin: str, destination: str) -> Dict[str, Any]:
        """
        Routes API (Directions) を呼び出してルート候補を取得する
        SSE分割呼び出し用の公開メソッド
        """
        if not self.gmaps:
            return {"error": "Google Maps API Key missing"}
        
        try:
            directions_result = self.gmaps.directions(
                origin,
                destination,
                mode="walking",
                alternatives=True # 複数ルート候補を取得
            )
            return {"routes": directions_result, "count": len(directions_result) if directions_result else 0}
        except Exception as e:
            return {"error": f"Directions API Failed: {str(e)}"}
    
    async def analyze_single_route(self, route: Dict[str, Any], on_progress: Any = None) -> Dict[str, Any]:
        """
        単一ルートのリスク分析を行う
        SSE分割呼び出し用の公開メソッド
        on_progress: (point_data) -> void コールバック
        """
        polyline = route.get("overview_polyline", {}).get("points")
        if not polyline:
            return None
        
        # リスク分析 (Bottleneck Logic)
        risk_analysis = await self._analyze_route_risks(polyline, on_progress)
        
        return {
            "summary": route.get("summary"),
            "legs": route.get("legs"),
            "overview_polyline": route.get("overview_polyline"),
            "risk_analysis": risk_analysis,
            "score": risk_analysis["score"]
        }
        
    async def _analyze_route_risks(self, polyline_str: str, on_progress: Any = None) -> Dict[str, Any]:
        """
        [Core Logic] ポリラインを分解し、ボトルネック評価を行う
        """
        # 1. Decode Polyline -> 座標リスト
        path_points = self._decode_polyline(polyline_str)

        # 2. Resample -> 等間隔のポイント生成 (パフォーマンス調整)
        sampled_points = self._resample_path(path_points, interval_meters=self.SAMPLING_INTERVAL_METERS)
        
        # 3. Scan -> 各ポイントのリスク評価 (並列実行)
        # 標高データの一括取得 (Batch API Call)
        elevations = []
        if self.elevation_service:
            print("⛰️ [Navigator] Fetching elevation data (Batch)...", flush=True)
            elevations = self.elevation_service.get_elevations(sampled_points)
        else:
            elevations = [0.0] * len(sampled_points)
 
        # 全ポイントの並列処理タスクを作成
        tasks = []
        print(f"🚀 [Navigator] Starting parallel analysis for {len(sampled_points)} points...", flush=True)

        # ラッパー関数: 分析完了時にコールバックを呼ぶ
        async def analyze_wrapper(i, point, elevation):
            result = await self._analyze_single_point(i, point, elevation)
            if on_progress:
                try:
                    # コールバックは同期関数の想定 (Queue.putなど)
                    on_progress(result)
                except Exception as e:
                    print(f"⚠️ Callback Error: {e}")
            return result

        for i, point in enumerate(sampled_points):
            # Process each point concurrently
            elevation = elevations[i]
            # task = self._analyze_single_point(i, point, elevation)
            task = analyze_wrapper(i, point, elevation)
            tasks.append(task)
        
        # Run all tasks in parallel
        # return_exceptions=True to prevent one failure from crashing everything
        results = await asyncio.gather(*tasks, return_exceptions=True)

        min_route_score = 100.0
        details = []

        for res in results:
            if isinstance(res, Exception):
                print(f"⚠️ Point Analysis Error: {res}")
                continue
            
            # Aggregate results
            point_score = res["score"]
            if point_score < min_route_score:
                min_route_score = point_score
            
            details.append(res)
            
        print(f"🏁 [Navigator] Analysis complete. Min Score: {min_route_score}", flush=True)

        # 4. Final Score = Bottleneck (Minimum Score)
        return {
            "score": min_route_score, 
            "details": details,
            "risk_factors": list(set([r for d in details for r in d["risks"]]))
        }

    async def _analyze_single_point(self, index: int, point: Dict[str, float], elevation: float) -> Dict[str, Any]:
        """
        単一地点のリスク評価を行う (並列実行用)
        Network I/Oを含む重い処理 (Vision, Solar, Places) を非同期/スレッドで実行する
        """
        current_risks = []
        point_score = 100.0

        # --- 1. Elevation / Flood Risk (Already fetched, fast CPU calc) ---
        if self.elevation_service:
            deduction, label = self.elevation_service.evaluate_flood_risk(elevation)
            if deduction > 0:
                point_score -= deduction
                current_risks.append(f"FLOOD_RISK: {label} ({elevation:.1f}m)")

        # --- 2. Visual Vibe Check (Analyst Agent) - IO Bound ---
        if self.analyst:
            # Run blocking synchronous code in a separate thread
            # print(f"👁️ Point {index}: Analyzing visual vibe...", flush=True)
            try:
                loop = asyncio.get_running_loop()
                vibe_result = await loop.run_in_executor(
                    None, 
                    self.analyst.analyze_location_vibe, 
                    point["lat"], 
                    point["lng"]
                )
                
                vibe_score = vibe_result.get("safety_score", 50)
                atmosphere = vibe_result.get("atmosphere", "Unknown")
                
                vibe_penalty = (100 - vibe_score) * 0.2
                if vibe_penalty > 0:
                    point_score -= vibe_penalty
                    current_risks.append(f"VIBE_RISK: {atmosphere}")
            except Exception as e:
                print(f"⚠️ Point {index} Vision Error: {e}")

        # --- 3. Physical & Social Safety (Solar & Places) - IO Bound ---
        
        # B. Solar (Shadow/Darkness)
        if self.solar_service:
            try:
                loop = asyncio.get_running_loop()
                solar_deduction, solar_label = await loop.run_in_executor(
                    None,
                    self.solar_service.evaluate_darkness_risk,
                    point["lat"],
                    point["lng"]
                )
                if solar_deduction > 0:
                    point_score -= solar_deduction
                    current_risks.append(f"SHADOW_RISK: {solar_label}")
            except Exception as e:
                print(f"⚠️ Point {index} Solar Error: {e}")

        # C. Places (Safety Spots)
        if self.places_service:
            try:
                loop = asyncio.get_running_loop()
                bonus, spot_details = await loop.run_in_executor(
                    None,
                    self.places_service.evaluate_safety_bonus,
                    point["lat"],
                    point["lng"]
                )
                if bonus > 0:
                    point_score += bonus
                    for d in spot_details:
                        current_risks.append(f"SAFETY_BONUS: {d}")
            except Exception as e:
                print(f"⚠️ Point {index} Places Error: {e}")

        # --- 4. Hazard Map Checks (Flood, Tsunami, Landslide) - Async IO ---
        # 警報が発令されている場合のみ、該当するハザードマップをチェック
        
        # ヘルパー: 指定したハザードタイプに対応する警報がアクティブかチェック
        def _is_hazard_alert_active(hazard_type: str) -> bool:
            """active_alertsに該当するハザードタイプの警報があるか確認"""
            for alert in self.active_alerts:
                mapped = self.ALERT_TO_HAZARD.get(alert, "")
                if mapped == hazard_type:
                    return True
            return False
        
        # D. Flood Hazard (浸水ハザードマップ) - 大雨警報/洪水警報発令時のみ
        if _is_hazard_alert_active("flood"):
            if hasattr(self, 'flood_service') and self.flood_service:
                try:
                    is_flood, depth = await self.flood_service.check_flood_risk(
                        point["lat"], point["lng"]
                    )
                    if is_flood:
                        # 浸水深に応じたペナルティ
                        if depth and "10m" in depth:
                            point_score -= 50
                        elif depth and ("5m" in depth or "3m" in depth):
                            point_score -= 35
                        elif depth and "0.5m〜" in depth:
                            point_score -= 20
                        else:
                            point_score -= 10
                        current_risks.append(f"FLOOD_HAZARD: 浸水想定区域 ({depth})")
                except Exception as e:
                    print(f"⚠️ Point {index} Flood Hazard Error: {e}")
        
        # E. Tsunami Hazard (津波ハザードマップ) - 津波警報/注意報発令時のみ
        if _is_hazard_alert_active("tsunami"):
            if hasattr(self, 'tsunami_service') and self.tsunami_service:
                try:
                    is_tsunami, depth = await self.tsunami_service.check_tsunami_risk(
                        point["lat"], point["lng"]
                    )
                    if is_tsunami:
                        # 津波浸水は高ペナルティ
                        if depth and "10m" in depth:
                            point_score -= 60
                        elif depth and "5m" in depth:
                            point_score -= 45
                        elif depth and ("2m" in depth or "1m" in depth):
                            point_score -= 30
                        else:
                            point_score -= 15
                        current_risks.append(f"TSUNAMI_HAZARD: 津波浸水想定区域 ({depth})")
                except Exception as e:
                    print(f"⚠️ Point {index} Tsunami Hazard Error: {e}")
        
        # F. Landslide Hazard (土砂災害ハザードマップ) - 土砂災害警戒情報発令時のみ
        if _is_hazard_alert_active("landslide"):
            if hasattr(self, 'landslide_service') and self.landslide_service:
                try:
                    is_landslide, risk_type = await self.landslide_service.check_landslide_risk(
                        point["lat"], point["lng"]
                    )
                    if is_landslide:
                        point_score -= 40
                        current_risks.append(f"LANDSLIDE_HAZARD: {risk_type}")
                except Exception as e:
                    print(f"⚠️ Point {index} Landslide Hazard Error: {e}")

        # Clamp score
        if point_score < 0: point_score = 0
        if point_score > 100: point_score = 100

        return {
            "lat": point["lat"],
            "lng": point["lng"],
            "elevation": elevation,
            "score": point_score,
            "risks": current_risks
        }


    def _decode_polyline(self, polyline_str: str) -> List[Dict[str, float]]:
        """
        Encoded Polylineをデコードする (Google Maps Algorithm)
        """
        import googlemaps
        # 実際には注入された client を使うか、utility関数を使う
        return googlemaps.convert.decode_polyline(polyline_str)

    def _resample_path(self, points: List[Dict[str, float]], interval_meters: float) -> List[Dict[str, float]]:
        """
        [重要] 座標リストを等間隔(100m)にサンプリングし直す
        単純な間引きではなく、線上の座標を補間(Interpolate)して計算する
        """
        if not points:
            return []
            
        resampled = [points[0]] # スタート地点は必ず含める
        current_dist_buffer = 0.0
        
        from geopy.distance import geodesic
        import math
        
        # スタート地点は必ず含める
        resampled = [points[0]] 
        current_dist_buffer = 0.0
        
        total_original_dist = 0.0
        
        print(f"📏 [Sampling] Original points: {len(points)}", flush=True)

        for i in range(len(points) - 1):
            p1 = points[i]
            p2 = points[i+1]
            
            # 2点間の距離 (meters)
            segment_dist = geodesic((p1['lat'], p1['lng']), (p2['lat'], p2['lng'])).meters
            total_original_dist += segment_dist
            
            if segment_dist == 0:
                continue

            # このセグメント内で何回サンプリングできるか
            # buffer + segment_dist >= interval
            
            remaining_dist = segment_dist
            progress_on_segment = 0.0 # このセグメント上でどれだけ進んだか
            
            # 次のサンプリングポイントまでの距離
            dist_to_next_sample = interval_meters - current_dist_buffer
            
            while remaining_dist >= dist_to_next_sample:
                # 補間点を計算して追加
                # 線形補間 Ratio
                ratio = (progress_on_segment + dist_to_next_sample) / segment_dist
                
                new_lat = p1['lat'] + (p2['lat'] - p1['lat']) * ratio
                new_lng = p1['lng'] + (p2['lng'] - p1['lng']) * ratio
                
                resampled.append({"lat": new_lat, "lng": new_lng})
                
                # 更新
                remaining_dist -= dist_to_next_sample
                progress_on_segment += dist_to_next_sample
                
                # 次の点までの距離は interval_meters まるまる必要になる
                current_dist_buffer = 0.0
                dist_to_next_sample = interval_meters
            
            # 残りの距離をバッファに加算
            current_dist_buffer += remaining_dist
            
        print(f"📏 [Sampling] Total Distance: {total_original_dist:.1f}m -> {len(resampled)} points (Interval: {interval_meters}m)", flush=True)
        return resampled
