from pydantic import BaseModel, Field
from typing import List, Optional

# --- Input Models (Geminiへの入力) ---

class WeatherInfo(BaseModel):
    condition: str = Field(..., description="晴れ, 雨, 台風 etc.")
    temperature: float = Field(..., description="気温 (度)")
    rain_1h: float = Field(0.0, description="1時間降水量 (mm)")
    wind_speed: float = Field(0.0, description="風速 (m/s)")
    warnings: List[str] = Field(default_factory=list, description="発令中の警報リスト")

class HazardInfo(BaseModel):
    flood_depth: float = Field(0.0, description="浸水想定深 (m)")
    landslide_risk: bool = Field(False, description="土砂災害警戒区域か")
    tsunami_risk: bool = Field(False, description="津波浸水想定区域か")

class SolarInfo(BaseModel):
    """Solar APIからの環境光/影データ"""
    sunshine_hours: float = Field(..., description="年間日照時間 (暗さの代理指標)")
    carbon_offset: float = Field(0.0, description="CO2削減効果 (今回は無視)")

class PlaceInfo(BaseModel):
    """Places APIからの周辺施設情報"""
    safety_spots_count: int = Field(0, description="周辺(100m)の交番・コンビニ数")
    nearest_spot_name: Optional[str] = Field(None, description="最も近い安全施設の名前")

class SafetyContext(BaseModel):
    """リスク評価エージェントへの入力コンテキスト"""
    mode: str = Field(..., description="'NORMAL' or 'EMERGENCY'")
    weather: WeatherInfo
    hazard: HazardInfo
    solar: Optional[SolarInfo] = Field(None, description="[NEW] 暗さ判定用データ")
    places: Optional[PlaceInfo] = Field(None, description="[NEW] 逃げ込み場所データ")
    crime_rate: str = Field("LOW", description="治安レベル (LOW, MEDIUM, HIGH)")

# --- Output Models (Geminiからの構造化出力) ---

class RiskAnalysis(BaseModel):
    """Geminiが生成するリスク評価結果"""
    risk_score: int = Field(..., description="危険度スコア (0-100). 100が最も危険")
    detected_risks: List[str] = Field(..., description="検知された具体的なリスク要因 (FLOOD, DARKNESS, etc.)")
    reasoning: str = Field(..., description="なぜそのスコアになったかの理由説明")
    suggested_action: str = Field(..., description="ユーザーへの推奨行動 (例: '高台へ避難してください')")
