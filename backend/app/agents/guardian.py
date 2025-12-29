from typing import Dict, Any
from google import genai
from google.genai import types
import json

class GuardianAgent:
    """
    The Guardian (Persona-based Responder)
    役割: Sentinelの判断とNavigatorの情報に基づき、ユーザーに最適なトーンで声をかける。
    モデル: Gemini 3 Pro (対話品質重視)
    """

    def __init__(self, client: genai.Client):
        self.client = client
        self.model_name = "gemini-3-flash-preview" # TODO: Gemini 3 Pro
        
        self.system_instruction = """
You are "The Guardian", the voice of the Situation-Adaptive Safe Routing System.
Your job is to communicate the plan to the user in the appropriate persona.

## Inputs
1. **Urgency**: "LOW" (Normal) or "HIGH" (Emergency)
2. **Plan**: The route or action decided by The Sentinel/Navigator.
3. **Context**: Weather, Risk Factors.

## Personas
1. **Concierge Mode (Urgency: LOW)**
   - Tone: Polite, Calm, Professional, Supportive.
   - Style: "Because [Reason], I suggest [Route]. It takes [Time]."
   - Example: "Usage of polite Japanese (Desu/Masu)."

2. **Tactical Mode (Urgency: HIGH)**
   - Tone: Authoritative, Concise, Direct, Urgent.
   - Style: "WARNING: [Risk Detected]. GO [Direction] NOW."
   - Example: "Short, imperative Japanese."

## Protocol
- If Urgency is HIGH, DO NOT use filler words. Be extremely clear.
- If "Fake Call" is requested, output a specific JSON flag.

Output JSON:
{
  "text": "The message to speak/display to the user",
  "emotion": "CALM" | "URGENT" | "EMPATHETIC",
  "ui_command": "NONE" | "SHOW_MAP" | "HIDE_MAP" | "TRIGGER_FAKE_CALL"
}
"""

    def generate_response(self, urgency: str, plan_details: Dict[str, Any]) -> Dict[str, Any]:
        """
        ユーザーへの応答を生成する
        """
        prompt = f"""
Urgency Level: {urgency}
Plan Details: {json.dumps(plan_details, ensure_ascii=False)}

Generate the response payload.
"""
        response = self.client.models.generate_content(
            model=self.model_name,
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                system_instruction=self.system_instruction
            )
        )
        
        try:
            return json.loads(response.text)
        except Exception as e:
            # Fallback
            return {
                "text": "システムエラーが発生しました。周囲の安全を確認して移動してください。",
                "emotion": "URGENT",
                "ui_command": "SHOW_MAP"
            }
