import os
import requests

class StreetViewService:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "https://maps.googleapis.com/maps/api/streetview"

    def get_static_image_url(self, lat: float, lng: float, heading: int = 0, pitch: int = 0, fov: int = 90) -> str:
        """
        指定座標のストリートビュー画像URLを生成する
        """
        params = [
            f"size=600x400",
            f"location={lat},{lng}",
            f"heading={heading}",
            f"pitch={pitch}",
            f"fov={fov}",
            f"key={self.api_key}"
        ]
        return f"{self.base_url}?{'&'.join(params)}"

    def check_availability(self, lat: float, lng: float) -> bool:
        """
        指定座標にストリートビューが存在するか確認する (Metadata API)
        """
        meta_url = f"{self.base_url}/metadata?location={lat},{lng}&key={self.api_key}"
        try:
            resp = requests.get(meta_url, timeout=3.0)
            data = resp.json()
            return data.get("status") == "OK"
        except Exception as e:
            print(f"⚠️ Street View Metadata Check Failed: {e}")
            return False
