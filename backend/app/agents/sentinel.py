from typing import Dict, Any, List
from google import genai
from google.genai import types
import os
import json
from models.risk_models import SafetyContext, RiskAnalysis

class SentinelAgent:
    """
    The Sentinel (Dispatcher Agent)
    役割: ユーザーの入力とコンテキストを分析し、適切な専門エージェント(Tools)を呼び出す。
    モデル: Gemini 3 Pro (推定) -> 推論能力(CoT)を重視
    """

    def __init__(self, client: genai.Client):
        self.client = client
        self.model_name = "gemini-3-pro-preview"  # Gemini 3 Pro (推論能力重視)
        
        self.system_instruction = """
You are "The Sentinel", the central dispatcher for the "Situation-Adaptive Safe Routing System".
Your goal is to protect the user by analyzing their situation and coordinating specialized agents.

## Your Capabilities
You do not execute tools yourself. Instead, you PLAN which tools/agents to use.

## Available Agents (Tools)
1. **Navigator**: Calculates routes and checks physical risks (Weather, Disaster, Crime).
2. **Analyst**: Analyzes visual data (Street View, User Camera) for "vibe" checks.
3. **Guardian**: Generates the final response to the user (Consoling, Instructing).

## Process (Chain of Thought)
1. **Observe**: Analyze the user's input and current SafetyContext.
2. **Reason**: Determine if the situation is NORMAL or EMERGENCY.
   - If user seems panicked (e.g., "Help!", "Scared"), switch to EMERGENCY mode.
3. **Plan**: Decide which Agent to call next.
   - Need a route? -> Call Navigator.
   - Route looks dark/sketchy? -> Call Navigator (Solar) or Analyst (Vision).
   - Analysis done? -> Call Guardian to respond.

## Language Requirement
- **ALWAYS output `thought` and `instruction_to_agent` in JAPANESE.**
- Ensure natural, professional Japanese suitable for a navigation assistant system.

Output your thought process in JSON format.
"""

    def analyze_status(self, user_input: str, context: SafetyContext) -> Dict[str, Any]:
        """
        ユーザー入力とコンテキストから、次に何をすべきかを判断する
        """
        prompt = f"""
User Input: "{user_input}"
Current Mode: {context.mode}
Weather: {context.weather.condition}, Rain: {context.weather.rain_1h}mm
Alerts: {context.weather.warnings}

Based on this, what is the immediate next step?
Return JSON with:
{{
  "thought": "Your reasoning here...",
  "detected_urgency": "LOW" | "HIGH",
  "next_agent": "NAVIGATOR" | "ANALYST" | "GUARDIAN",
  "instruction_to_agent": "Specific instruction for the next agent"
}}
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
            print(f"JSON Parse Error: {e}")
            return {
                "thought": "Error parsing Agent response",
                "detected_urgency": "HIGH", # Fail-safe
                "next_agent": "GUARDIAN",
                "instruction_to_agent": "System error. Please guide user manually."
            }
