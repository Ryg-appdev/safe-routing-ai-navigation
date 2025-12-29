import requests
import os
from typing import List, Dict, Any

class PlacesService:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://places.googleapis.com/v1/places:searchNearby"

    def find_nearby_safety_spots(self, lat: float, lng: float, radius_meters: int = 100) -> List[Dict[str, Any]]:
        """
        指定座標の周辺にある「安全スポット」を検索する。
        対象: 警察署, 病院, 消防署, コンビニ
        """
        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "places.displayName,places.primaryType"
        }
        
        # New Places API (v1)
        body = {
            "includedPrimaryTypes": [
                "police", 
                "hospital", 
                "fire_station", 
                "convenience_store"
            ],
            "maxResultCount": 5,
            "locationRestriction": {
                "circle": {
                    "center": {
                        "latitude": lat,
                        "longitude": lng
                    },
                    "radius": radius_meters
                }
            }
        }
        
        try:
            resp = requests.post(self.base_url, headers=headers, json=body, timeout=3.0)
            if resp.status_code == 200:
                data = resp.json()
                return data.get("places", [])
            else:
                print(f"⚠️ Places API Error {resp.status_code}: {resp.text}")
                return []
        except Exception as e:
            print(f"⚠️ Places API Request Failed: {e}")
            return []

    def evaluate_safety_bonus(self, lat: float, lng: float) -> tuple[float, List[str]]:
        """
        安全スポットがあればスコアを加点する
        """
        places = self.find_nearby_safety_spots(lat, lng)
        if not places:
            return (0.0, [])
            
        bonus = 0.0
        details = []
        
        for p in places:
            p_type = p.get("primaryType", "")
            name = p.get("displayName", {}).get("text", "Unknown")
            
            if p_type == "police":
                bonus += 10.0
                details.append(f"近くに交番あり: {name}")
            elif p_type in ["hospital", "fire_station"]:
                bonus += 8.0
                details.append(f"近くに緊急施設あり: {name}")
            elif p_type == "convenience_store":
                bonus += 5.0 # 明るい、人がいる
                details.append(f"近くにコンビニあり: {name}")
                
        # Cap bonus
        bonus = min(bonus, 20.0)
        return (bonus, details)
