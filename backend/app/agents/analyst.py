from google import genai
from google.genai import types
import os
import json

class AnalystAgent:
    def __init__(self, client: genai.Client):
        self.client = client
        self.model_name = "gemini-3-flash-preview"
        
        api_key = os.environ.get("GOOGLE_MAPS_API_KEY")
        if api_key:
            from services.street_view_service import StreetViewService
            self.street_view = StreetViewService(api_key)
        else:
            self.street_view = None

    def analyze_location_vibe(self, lat: float, lng: float) -> dict:
        """
        指定地点のストリートビュー画像を解析し、雰囲気スコア(0-100)と解説を返す
        """
        if not self.street_view:
            return {"score": 50, "reason": "No Street View Service available"}

        # 1. 画像URL取得
        image_url = self.street_view.get_static_image_url(lat, lng)
        
        # 2. 画像が存在するか確認 (省略可能だが丁寧にするなら)
        # availability = self.street_view.check_availability(lat, lng)
        # if not availability:
        #     return {"score": 50, "reason": "No Street View image available"}
        
        # 3. Gemini Vision API Call
        prompt = """
        Analyze this street view image for pedestrian safety at night.
        Output ONLY JSON:
        {
          "safety_score": 0-100 (100 is very safe, bright, populated. 0 is dark, abandoned, dangerous),
          "atmosphere": "Short ONE-LINE description of the vibe in JAPANESE (e.g. '賑やかな繁華街', '街灯の少ない路地', '閑静な住宅街')",
          "lighting": "Low/Medium/High",
          "risk_factors": ["list", "of", "risks", "in", "JAPANESE"]
        }
        """
        
        try:
            # Note: Assuming getting the image bytes is needed for the client, 
            # OR pass the URL if the model supports it. 
            # Gemini 2.0 Flash typically supports image input.
            # For simplicity, let's assume we fetch bytes or pass URL if supported.
            # The current SDK supports Part.from_uri if it's a GCS URI, or bytes.
            # To be safe/standard with current genai library, let's download bytes.
            
            import requests
            img_data = requests.get(image_url).content
            
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=[
                    prompt,
                    types.Part.from_bytes(data=img_data, mime_type="image/jpeg")
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json"
                )
            )
            
            # response.text アクセス時のWarning抑制のため、手動でテキストパートを結合
            text_content = ""
            if response.candidates and response.candidates[0].content.parts:
                for part in response.candidates[0].content.parts:
                    if part.text:
                        text_content += part.text
            
            result = json.loads(text_content)
            return result

        except Exception as e:
            print(f"⚠️ Analyst Vision Error: {e}")
            return {"score": 50, "reason": f"Analysis failed: {str(e)}"}
