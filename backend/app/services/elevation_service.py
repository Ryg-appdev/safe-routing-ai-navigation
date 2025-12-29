import googlemaps
from typing import List, Dict, Any, Optional

class ElevationService:
    def __init__(self, client: googlemaps.Client):
        self.client = client

    def get_elevations(self, locations: List[Dict[str, float]]) -> List[float]:
        """
        指定された座標リストの標高を取得する
        locations: [{"lat": 35.0, "lng": 139.0}, ...]
        return: [10.5, 12.0, ...] (meters)
        """
        if not self.client:
            print("⚠️ Google Maps Client is not initialized.")
            return [0.0] * len(locations)

        if not locations:
            return []

        # Google Maps Elevation API format: (lat, lng) tuples or dictionary
        # library accepts list of (lat, lng) or list of dicts/points
        
        # Convert to list of (lat, lng) tuples for robust handling
        latlngs = [(loc['lat'], loc['lng']) for loc in locations]

        try:
            # Batching is handled by the client automatically typically, 
            # but explicit batching (512 locations) is safer for very long routes.
            # Assuming short routes for MVP.
            results = self.client.elevation(latlngs)
            
            # Extract elevation values
            # results order matches input order
            elevations = [r['elevation'] for r in results]
            return elevations
            
        except Exception as e:
            print(f"⚠️ Elevation API Error: {e}")
            # Fallback: return 0.0s so processing doesn't crash
            return [0.0] * len(locations)

    def evaluate_flood_risk(self, elevation: float) -> tuple[float, str]:
        """
        標高から簡易的な浸水リスクを判定する (Hackathon Simple Logic)
        :return: (risk_score_deduction, risk_description)
        """
        # 簡易ロジック: 標高が低いほどリスクが高いとみなす
        # 例えば海抜3m以下は高潮/津波リスクありとする
        if elevation < 0:
             return (50.0, "Zero Meter Region")
        elif elevation < 3.0:
             return (30.0, "Low Elevation (<3m)")
        elif elevation < 5.0:
             return (10.0, "Low Elevation (<5m)")
        else:
             return (0.0, "Safe Elevation")
