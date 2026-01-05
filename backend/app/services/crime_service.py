from typing import List, Dict, Tuple, Optional, Any
from geopy.distance import geodesic

class CrimeService:
    """
    治安統計データを提供するサービス (Mock implementation)
    """

    # Mock Data: 治安懸念エリア (Lat, Lng, Radius(m), RiskLevel, Description)
    # RiskLevel: DANGER (High), WARNING (Mid)
    DANGER_ZONES = [
        # 歌舞伎町エリア (High Risk)
        {
            "name": "Kabukicho",
            "lat": 35.6938,
            "lng": 139.7036,
            "radius": 300,
            "level": "DANGER",
            "type": "繁華街トラブル・客引き",
            "penalty": 40
        },
        # 六本木エリア (Mid Risk)
        {
            "name": "Roppongi",
            "lat": 35.6628,
            "lng": 139.7315,
            "radius": 300,
            "level": "WARNING",
            "type": "夜間トラブル・騒音",
            "penalty": 20
        },
        # 渋谷センター街 (Mid Risk)
        {
            "name": "Shibuya Center-gai",
            "lat": 35.6604,
            "lng": 139.6990,
            "radius": 200,
            "level": "WARNING",
            "type": "混雑・トラブル",
            "penalty": 20
        },
        # 池袋北口エリア (High Risk)
        {
            "name": "Ikebukuro North",
            "lat": 35.7318,
            "lng": 139.7118,
            "radius": 250,
            "level": "DANGER",
            "type": "治安懸念",
            "penalty": 40
        }
    ]

    def check_crime_risk(self, lat: float, lng: float) -> Tuple[bool, Optional[Dict[str, Any]]]:
        """
        指定された座標が危険エリアに含まれるかチェックする
        Returns: (is_risky, risk_details)
        """
        point = (lat, lng)

        for zone in self.DANGER_ZONES:
            zone_center = (zone["lat"], zone["lng"])
            distance = geodesic(point, zone_center).meters

            if distance <= zone["radius"]:
                return True, {
                    "level": zone["level"],
                    "type": zone["type"],
                    "penalty": zone["penalty"],
                    "description": f"CRIME_RISK: {zone['type']} ({zone['level']})"
                }
        
        return False, None

# Singleton instance
crime_service = CrimeService()
