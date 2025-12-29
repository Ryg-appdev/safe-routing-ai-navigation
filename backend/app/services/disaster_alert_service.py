"""
災害アラート統合サービス
地震・津波・気象警報・土砂災害を統合して判定する
"""

import asyncio
from typing import Optional
from pydantic import BaseModel
from datetime import datetime

from .earthquake_service import earthquake_service, DisasterAlerts
from .weather_warning_service import weather_warning_service, WeatherAlerts


class AlertInfo(BaseModel):
    """警報情報"""
    type: str  # "TSUNAMI" | "EARTHQUAKE" | "RAIN" | "FLOOD" | "LANDSLIDE" | "NONE"
    level: str  # "critical" | "warning" | "advisory" | "none"
    title: str  # 表示用タイトル
    message: str  # 表示用メッセージ
    auto_emergency: bool  # 自動で非常時モードにするか
    icon: str  # 絵文字アイコン


class UnifiedAlerts(BaseModel):
    """統合警報情報"""
    alerts: list[AlertInfo] = []
    has_critical_alert: bool = False
    primary_alert: Optional[AlertInfo] = None  # 最優先の警報
    should_emergency_mode: bool = False  # 非常時モードにすべきか
    checked_at: str = ""


class DisasterAlertService:
    """
    災害アラート統合サービス
    全ての警報ソースを統合して判定する
    """
    
    def __init__(self):
        pass
    
    async def get_unified_alerts(self, municipalities: list[str] = None) -> UnifiedAlerts:
        """
        全警報ソースから統合アラートを取得
        """
        municipalities = municipalities or []
        
        # 並列で全ソースから取得
        earthquake_alerts, weather_alerts = await asyncio.gather(
            earthquake_service.get_disaster_alerts(target_areas=municipalities),
            weather_warning_service.get_weather_alerts(municipalities),
            return_exceptions=True
        )
        
        # エラーハンドリング
        if isinstance(earthquake_alerts, Exception):
            print(f"⚠️ 地震情報取得エラー: {earthquake_alerts}")
            earthquake_alerts = DisasterAlerts()
        
        if isinstance(weather_alerts, Exception):
            print(f"⚠️ 気象警報取得エラー: {weather_alerts}")
            weather_alerts = WeatherAlerts()
        
        # アラートリストを構築
        alerts = []
        
        # 津波警報（最優先）
        if earthquake_alerts.alert_type == "TSUNAMI":
            alerts.append(AlertInfo(
                type="TSUNAMI",
                level="critical",
                title="津波警報",
                message=earthquake_alerts.alert_message or "津波警報が発令されています",
                auto_emergency=True,
                icon="🌊"
            ))
        
        # 地震情報
        if earthquake_alerts.alert_type == "EARTHQUAKE":
            alerts.append(AlertInfo(
                type="EARTHQUAKE",
                level="warning",
                title="地震情報",
                message=earthquake_alerts.alert_message or "地震が発生しました",
                auto_emergency=True,
                icon="🔴"
            ))
        
        # 気象警報
        if weather_alerts.has_major_alert:
            level = "critical" if any("特別" in w.level for w in weather_alerts.warnings) else "warning"
            alerts.append(AlertInfo(
                type=weather_alerts.alert_type or "RAIN",
                level=level,
                title=f"気象{weather_alerts.warnings[0].level if weather_alerts.warnings else '警報'}",
                message=weather_alerts.alert_message or "気象警報が発令されています",
                auto_emergency=True,
                icon="⚠️"
            ))
        
        # 警報なしの場合
        if not alerts:
            alerts.append(AlertInfo(
                type="NONE",
                level="none",
                title="警報・注意報なし",
                message="現在、警報・注意報は発令されていません",
                auto_emergency=False,
                icon="✅"
            ))
        
        # 最優先アラートを判定
        primary_alert = alerts[0] if alerts else None
        has_critical = any(a.level == "critical" for a in alerts)
        should_emergency = any(a.auto_emergency for a in alerts)
        
        return UnifiedAlerts(
            alerts=alerts,
            has_critical_alert=has_critical,
            primary_alert=primary_alert,
            should_emergency_mode=should_emergency and primary_alert and primary_alert.type != "NONE",
            checked_at=datetime.now().isoformat()
        )
    
    def get_pre_search_narrative(
        self, 
        is_emergency: bool, 
        alert: Optional[AlertInfo] = None
    ) -> str:
        """
        ルート検索前のナラティブを生成
        """
        if is_emergency and alert and alert.type != "NONE":
            # 警報に応じたメッセージ
            narratives = {
                "TSUNAMI": "🌊 津波警報が発令されています。高台への避難ルートを優先して案内します。",
                "EARTHQUAKE": "🔴 地震が発生しました。広い道を優先し、倒壊リスクのある建物を避けてご案内します。",
                "RAIN": "⚠️ 大雨警報が発令されています。低地や川の近くを避けてご案内します。",
                "FLOOD": "🌊 洪水警報が発令されています。浸水リスクのあるエリアを回避します。",
                "LANDSLIDE": "⛰️ 土砂災害警戒情報が発令されています。山沿いを避けてご案内します。",
            }
            return narratives.get(alert.type, "緊急モードです。安全を最優先したルートを検索します。")
        
        elif is_emergency:
            return "緊急モードに切り替えました。安全を最優先したルートを検索します。"
        
        else:
            # 時間帯に応じた挨拶
            hour = datetime.now().hour
            if hour < 10:
                return "おはようございます。今日も安全なルートでご案内します。"
            elif hour < 17:
                return "こんにちは！目的地を入力してナビを開始してください。"
            elif hour < 22:
                return "お疲れ様です。帰り道は明るい道をご案内しますね。"
            else:
                return "深夜のお出かけですね。安全なルートを優先してご案内します。"


# シングルトンインスタンス
disaster_alert_service = DisasterAlertService()
