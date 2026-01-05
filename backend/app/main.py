import os
import json
import functions_framework
from flask import jsonify, Response
from google import genai
from dotenv import load_dotenv
import asyncio
import time
import warnings

# Suppress annoying warnings
import logging
import sys

# Nuclear option for warnings
def warn_with_log(message, category, filename, lineno, file=None, line=None):
    log = logging.getLogger("py.warnings")
    msg = f"{message}"
    if "non-text parts" in msg:
        return # COMPLETELY IGNORE
    log.warning(f"{filename}:{lineno}: {category.__name__}: {message}")

warnings.showwarning = warn_with_log
warnings.filterwarnings("ignore", category=UserWarning, module='urllib3')
logging.getLogger("google").setLevel(logging.ERROR)
logging.getLogger("google_generativeai").setLevel(logging.ERROR)
logging.getLogger("tornado.access").setLevel(logging.ERROR)

# Agent Imports
# 注意: ディレクトリ構成に合わせて適切にimportパスを調整する必要があります
from agents.sentinel import SentinelAgent
from agents.navigator import NavigatorAgent
from agents.guardian import GuardianAgent
from models.risk_models import SafetyContext, WeatherInfo, HazardInfo

# Disaster Alert Service
from services.disaster_alert_service import disaster_alert_service
from services.geocode_service import GeocodeService

# Load Environment Variables
# Local Development: Load from ../.env
env_path = os.path.join(os.path.dirname(__file__), '../.env')
load_dotenv(dotenv_path=env_path)

# Initialize Gemini Client
api_key = os.getenv("GEMINI_API_KEY")
if not api_key:
    # 実際はログ出力やエラーハンドリングを行う
    print("WARNING: GEMINI_API_KEY is not set.")
    # モック開発用などで落ちないようにする、あるいはここでraise Exceptionするかはプロジェクト方針による
    # 今回はNoneのままいくが、各Agent内でエラーになる可能性あり
    
client = genai.Client(api_key=api_key)

# Initialize Agents
sentinel = SentinelAgent(client)
navigator = NavigatorAgent(client)
guardian = GuardianAgent(client)

# Initialize Geocode Service
import googlemaps
gmaps_key = os.getenv("GOOGLE_MAPS_API_KEY")
if gmaps_key:
    gmaps_client = googlemaps.Client(key=gmaps_key)
    geocode_service = GeocodeService(gmaps_client)
else:
    print("WARNING: GOOGLE_MAPS_API_KEY not set. GeocodeService disabled.")
    geocode_service = None

@functions_framework.http
def handle_route_request(request):
    """
    Cloud Run Entry Point
    POST /findSafeRoute
    Body: { "origin": "渋谷", "destination": "新宿", "context": {...} }
    """
    
    # 1. Parse Request
    try:
        # print("\n\n🔵 === [START] Request Received from Simulator ===", flush=True)
        start_time = time.time()
        req_json = request.get_json(silent=True)
        if not req_json:
            return jsonify({"error": "Invalid JSON"}), 400
            
        origin = req_json.get("origin")
        destination = req_json.get("destination")
        # クライアントから送られてくるコンテキスト情報（任意）
        # なければデフォルトを作成
        context_data = req_json.get("context", {})
        
        # Build Safety Context
        # MVPでは気象データはバックエンド側で取得する想定だが、
        # ここでは簡易的にリクエストから受けるか、デフォルトを入れる
        weather = WeatherInfo(
            condition=context_data.get("weather_condition", "Clear"),
            temperature=context_data.get("temperature", 20.0),
            rain_1h=context_data.get("rain_1h", 0.0),
            warnings=context_data.get("warnings", [])
        )
        
        hazard = HazardInfo(
            flood_depth=0.0,
            landslide_risk=False,
            tsunami_risk=False
        )
        
        context = SafetyContext(
            mode=context_data.get("mode", "NORMAL"),
            weather=weather,
            hazard=hazard
        )
        
    except Exception as e:
        return jsonify({"error": f"Request parsing failed: {str(e)}"}), 400

    # 2. Check Disaster Alerts
    alert_info = None
    try:
        # Geocodingで正確な市区町村名を取得
        # geocode_service が利用できない場合はそのまま地名を使用
        origin_muni = origin
        dest_muni = destination
        
        if geocode_service:
            # print(f"🔍 Geocoding: {origin} -> ...")
            m1 = geocode_service.get_municipality_from_address(origin)
            if m1:
                origin_muni = m1
                # print(f"   Success: {m1}")
                
            # print(f"🔍 Geocoding: {destination} -> ...")
            m2 = geocode_service.get_municipality_from_address(destination)
            if m2:
                dest_muni = m2
                # print(f"   Success: {m2}")
        
        municipalities = [origin_muni, dest_muni]
        
        # asyncioのイベントループ対応
        import asyncio
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            loop = None
        
        if loop and loop.is_running():
            # 既存のループがある場合は新しいタスクとして実行
            import concurrent.futures
            with concurrent.futures.ThreadPoolExecutor() as executor:
                future = executor.submit(
                    asyncio.run,
                    disaster_alert_service.get_unified_alerts(municipalities)
                )
                unified_alerts = future.result(timeout=10)
        else:
            unified_alerts = asyncio.run(disaster_alert_service.get_unified_alerts(municipalities))
        
        if unified_alerts.primary_alert:
            alert_info = {
                "type": unified_alerts.primary_alert.type,
                "level": unified_alerts.primary_alert.level,
                "title": unified_alerts.primary_alert.title,
                "message": unified_alerts.primary_alert.message,
                "icon": unified_alerts.primary_alert.icon,
                "should_emergency_mode": unified_alerts.should_emergency_mode,
            }
            print(f"⚠️ Alert detected: {unified_alerts.primary_alert.title}")
    except Exception as e:
        print(f"⚠️ Alert check failed: {e}")

    # 2. Execution Flow (Agentic Orchestration)
    try:
        # A. Sentinel: Situation Analysis & Planning
        # 「これから何をすべきか？」を判断
        user_input = f"I want to go from {origin} to {destination}."
        sentinel_plan = sentinel.analyze_status(user_input, context)
        
        # Sentinelの判断結果ログ
        trace_log = [
            {"agent": "Sentinel", "output": sentinel_plan}
        ]
        
        # B. Navigator: Route Finding (if requested)
        # Sentinelが "NAVIGATOR" を指名した場合、またはルート探索が必要な場合
        # MVP簡易実装として、必ずNavigatorを呼ぶフローにするか、Sentinelの指示に従うか。
        # ここではSentinelの指示に従うロジックを組む。
        
        route_result = None
        if isinstance(sentinel_plan, list) and len(sentinel_plan) > 0:
            sentinel_plan = sentinel_plan[0]
        
        current_urgency = sentinel_plan.get("detected_urgency", "LOW")
        
        if sentinel_plan.get("next_agent") == "NAVIGATOR":
            # ルート探索とリスクスキャンを実行
            # Navigatorのメソッド呼び出し
            # 現状 navigator.py には find_safest_route と _analyze_route_risks がある
            # 本当は _analyze_route_risks は find_safest_route から呼ばれる内部メソッド
            
            # Risk Preferencesはコンテキストモードから簡易決定
            prefs = ["avoid_darkness"] if context.mode == "NORMAL" else ["shortest", "avoid_flood"]
            
            route_result = asyncio.run(navigator.find_safest_route(origin, destination, prefs))
            trace_log.append({"agent": "Navigator", "output": route_result})
        
        # C. Guardian: Final Response
        # Navigatorの結果(あれば)と、Sentinelの緊急度判断を元にメッセージ生成
        guardian_response = guardian.generate_response(
            urgency=current_urgency,
            plan_details={
                "origin": origin,
                "destination": destination,
                "sentinel_instruction": sentinel_plan.get("instruction_to_agent"),
                "route_found": route_result is not None,
                "route_summary": route_result.get("risk_assessment") if route_result else None
            }
        )
        trace_log.append({"agent": "Guardian", "output": guardian_response})

        # 3. Construct Final Response
        end_time = time.time()
        duration = end_time - start_time
        
        response = jsonify({
            "status": "success",
            "ui_view": "MAP_WITH_RISK" if route_result else "CHAT_ONLY",
            "narrative": guardian_response,
            "route_data": route_result,
            "alert_info": alert_info,
            "trace_log": trace_log,
            "execution_time": f"{duration:.2f}s"
        })
        # print(f"🟢 === [SUCCESS] Response Sent to Simulator (Duration: {duration:.2f}s) ===\n", flush=True)
        return response

    except Exception as e:
        # Global Error handler
        import traceback
        traceback.print_exc()
        return jsonify({
            "error": "Internal Processing Error", 
            "details": str(e),
            "trace": trace_log if 'trace_log' in locals() else []
        }), 500


@functions_framework.http
def handle_route_request_stream(request):
    """
    SSE Streaming版エントリポイント
    リアルタイムでエージェントの処理状況を送信
    """
    
    # 1. Parse Request outside generator to keep context
    print(f"\n\n🔵 === [START] SSE Stream Request Received ===", flush=True)
    req_json = request.get_json(silent=True)
    
    def generate():
        try:
            # req_json is captured from outer scope
            if not req_json:
                yield f"data: {json.dumps({'type': 'error', 'message': 'Invalid JSON'})}\n\n".encode('utf-8')
                return
            
            origin = req_json.get("origin")
            destination = req_json.get("destination")
            context_data = req_json.get("context", {})
            
            # ステータス送信
            # SSEのバッファリング対策のためのパディング (2KB)
            yield (": " + (" " * 2048) + "\n\n").encode('utf-8')
            yield f"data: {json.dumps({'type': 'status', 'agent': 'System', 'message': 'リクエスト解析完了'})}\n\n".encode('utf-8')
            
            # Build Context
            weather = WeatherInfo(
                condition=context_data.get("weather_condition", "Clear"),
                temperature=context_data.get("temperature", 20.0),
                rain_1h=context_data.get("rain_1h", 0.0),
                warnings=context_data.get("warnings", [])
            )
            hazard = HazardInfo(flood_depth=0.0, landslide_risk=False, tsunami_risk=False)
            context = SafetyContext(
                mode=context_data.get("mode", "NORMAL"),
                weather=weather,
                hazard=hazard
            )
            
            # 2. Disaster Alert Check
            yield f"data: {json.dumps({'type': 'status', 'agent': 'System', 'message': '警報情報を確認中...'})}\n\n".encode('utf-8')
            
            alert_info = None
            
            # --- [TEST] テスト用警報が設定されている場合、実際のAPIをスキップ ---
            test_alert = req_json.get("test_alert")
            if test_alert:
                # テスト用警報を使用
                alert_info = {
                    "type": "TEST",
                    "level": "WARNING",
                    "title": test_alert,
                    "message": f"[テスト用] {test_alert}が発令されています",
                    "icon": "⚠️",
                    "should_emergency_mode": True,
                }
                yield f"data: {json.dumps({'type': 'status', 'agent': 'System', 'message': f'[テスト] 警報設定: {test_alert}'})}\n\n".encode('utf-8')
                print(f"🧪 [TEST] Using test alert: {test_alert}", flush=True)
            
            # テスト警報がない場合は実際のAPIを使用
            if not test_alert:
                try:
                    # 駅名を区名に変換するヘルパー
                    # Geocodingで正確な市区町村名を取得
                    origin_muni = origin
                    dest_muni = destination
                    
                    if geocode_service:
                        m1 = geocode_service.get_municipality_from_address(origin)
                        if m1: origin_muni = m1
                        m2 = geocode_service.get_municipality_from_address(destination)
                        if m2: dest_muni = m2
                    
                    municipalities = [origin_muni, dest_muni]
                    
                    # asyncioのイベントループ対応
                    try:
                        loop = asyncio.get_running_loop()
                    except RuntimeError:
                        loop = None
                        
                    if loop and loop.is_running():
                        import concurrent.futures
                        with concurrent.futures.ThreadPoolExecutor() as executor:
                            future = executor.submit(
                                asyncio.run,
                                disaster_alert_service.get_unified_alerts(municipalities)
                            )
                            unified_alerts = future.result(timeout=10)
                    else:
                        unified_alerts = asyncio.run(disaster_alert_service.get_unified_alerts(municipalities))

                    if unified_alerts.primary_alert:
                        alert_info = {
                            "type": unified_alerts.primary_alert.type,
                            "level": unified_alerts.primary_alert.level,
                            "title": unified_alerts.primary_alert.title,
                            "message": unified_alerts.primary_alert.message,
                            "icon": unified_alerts.primary_alert.icon,
                            "should_emergency_mode": unified_alerts.should_emergency_mode,
                        }
                        alert_title = unified_alerts.primary_alert.title
                        yield f"data: {json.dumps({'type': 'status', 'agent': 'System', 'message': f'警報検出: {alert_title}'})}\n\n".encode('utf-8')
                    else:
                        yield f"data: {json.dumps({'type': 'status', 'agent': 'System', 'message': '警報なし'})}\n\n".encode('utf-8')
                except Exception as e:
                    err_msg = str(e)
                    yield f"data: {json.dumps({'type': 'status', 'agent': 'System', 'message': f'警報確認スキップ: {err_msg}'})}\n\n".encode('utf-8')

            # 3. Sentinel Analysis
            yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'sentinel', 'status': 'processing', 'progress': 30, 'message': '状況を解析中...'})}\n\n".encode('utf-8')
            
            user_input = f"I want to go from {origin} to {destination}."
            sentinel_plan = sentinel.analyze_status(user_input, context)
            
            trace_log = [{"agent": "Sentinel", "output": sentinel_plan}]
            yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'sentinel', 'status': 'complete', 'progress': 100, 'message': '解析完了'})}\n\n".encode('utf-8')
            
            # 4. Navigator (if needed)
            route_result = None
            if isinstance(sentinel_plan, list) and len(sentinel_plan) > 0:
                sentinel_plan = sentinel_plan[0]
            
            current_urgency = sentinel_plan.get("detected_urgency", "LOW")
            
            if sentinel_plan.get("next_agent") == "NAVIGATOR":
                yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'navigator', 'status': 'processing', 'progress': 10, 'message': 'ルート探索を開始...'})}\n\n".encode('utf-8')
                
                prefs = ["avoid_darkness"] if context.mode == "NORMAL" else ["shortest", "avoid_flood"]
                
                # Step 1: Routes API 呼び出し
                yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'navigator', 'status': 'processing', 'progress': 20, 'message': 'Google Routes APIにクエリ送信中...'})}\n\n".encode('utf-8')
                routes_data = navigator.fetch_routes(origin, destination)
                
                if "error" in routes_data:
                    error_msg = routes_data.get("error")
                    yield f"data: {json.dumps({'type': 'status', 'agent': 'Navigator', 'message': f'エラー: {error_msg}'})}\n\n".encode('utf-8')
                    route_result = routes_data
                else:
                    route_count = routes_data.get("count", 0)
                    yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'navigator', 'status': 'processing', 'progress': 35, 'message': f'{route_count}件のルート候補を取得'})}\n\n".encode('utf-8')
                    
                    routes_list = routes_data.get("routes", [])

                    # --- [NEW] 候補ルート（分析前）を送信 ---
                    try:
                        candidate_routes_payload = []
                        for r_idx, r in enumerate(routes_list):
                            poly = r.get("overview_polyline", {}).get("points")
                            if poly:
                                candidate_routes_payload.append({
                                    "index": r_idx,
                                    "polyline": poly
                                })
                        yield f"data: {json.dumps({'type': 'candidate_routes', 'routes': candidate_routes_payload})}\n\n".encode('utf-8')
                    except Exception as e:
                        print(f"⚠️ Failed to send candidate routes: {e}")

                    # Step 2: 各ルートのリスク分析
                    yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'navigator', 'status': 'processing', 'progress': 40, 'message': '各ポイントを評価中...'})}\n\n".encode('utf-8')
                    yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'analyst', 'status': 'processing', 'progress': 10, 'message': 'リスク分析を開始...'})}\n\n".encode('utf-8')
                    
                    # --- サンプリングポイントを先行送信（グレーマーカー表示用）---
                    # 【最適化】ユニークポイントのみ送信（重複排除済み）
                    try:
                        unique_sampling_points = navigator.get_unique_sampling_points(routes_list)
                        if unique_sampling_points:
                            yield f"data: {json.dumps({'type': 'sampling_points', 'points': unique_sampling_points})}\n\n".encode('utf-8')
                    except Exception as e:
                        print(f"⚠️ Failed to send sampling points: {e}")
                    
                    # Queue for streaming analysis points from thread
                    import queue
                    import concurrent.futures
                    
                    # --- [NEW] 警報情報をNavigatorに渡す（警報連動ハザードチェック用）---
                    if alert_info and alert_info.get("title"):
                        # 警報タイトルをactive_alertsに追加
                        navigator.active_alerts = [alert_info.get("title")]
                        print(f"🚨 [Navigator] Active alerts set: {navigator.active_alerts}", flush=True)
                    else:
                        navigator.active_alerts = []
                    
                    analysis_queue = queue.Queue()
                    
                    # Callback function (runs in thread)
                    def point_callback(data):
                        # data is dict with lat, lng, score, risks
                        analysis_queue.put(data)

                    # 全ルートを並列処理するヘルパー関数
                    # 【最適化】全ルートを一括分析（重複ポイント排除）
                    async def analyze_all_routes_batch(routes):
                        return await navigator.analyze_routes_batch(routes, on_progress=point_callback)
                    
                    # Run analysis in a separate thread so we can stream events from queue
                    executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
                    future = executor.submit(asyncio.run, analyze_all_routes_batch(routes_list))
                    
                    # Stream events while waiting for completion
                    while not future.done():
                        try:
                            # Non-blocking get with short timeout
                            point_data = analysis_queue.get(timeout=0.1)
                            # Stream point event
                            yield f"data: {json.dumps({'type': 'analysis_point', 'point': point_data})}\n\n".encode('utf-8')
                        except queue.Empty:
                            continue
                            
                    # Flush remaining items
                    while not analysis_queue.empty():
                        try:
                            point_data = analysis_queue.get_nowait()
                            yield f"data: {json.dumps({'type': 'analysis_point', 'point': point_data})}\n\n".encode('utf-8')
                        except queue.Empty:
                            break
                            
                    # 【変更】analyze_routes_batch は直接 evaluated_routes を返す
                    evaluated_routes = future.result()
                    executor.shutdown()
                    
                    yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'navigator', 'status': 'processing', 'progress': 85, 'message': f'{len(evaluated_routes)}件のルート評価完了'})}\n\n".encode('utf-8')
                    yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'analyst', 'status': 'complete', 'progress': 100, 'message': 'リスク分析完了'})}\n\n".encode('utf-8')
                    
                    # Step 3: 最適ルート選定
                    if evaluated_routes:
                        evaluated_routes.sort(key=lambda x: x["score"], reverse=True)
                        best_route = evaluated_routes[0]
                        score = best_route["score"]
                        yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'navigator', 'status': 'complete', 'progress': 100, 'message': '最適ルートを選定完了'})}\n\n".encode('utf-8')
                        
                        route_result = {
                            "route_id": "real_route_v1",
                            "waypoints": best_route["risk_analysis"].get("details", []),
                            "best_route_encoding": best_route["overview_polyline"]["points"],
                            "risk_assessment": {
                                "score": best_route["score"],
                                "safety_factors": ["Route evaluated by 100m bottleneck logic"],
                                "remaining_risks": [d for d in best_route["risk_analysis"]["details"] if d["score"] < 50]
                            }
                        }
                    else:
                        yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'navigator', 'status': 'complete', 'progress': 100, 'message': 'リスク分析失敗'})}\n\n".encode('utf-8')
                        route_result = {"error": "No valid routes after analysis"}
                
                # Payload optimization: Don't include huge route object in trace log
                trace_log.append({"agent": "Navigator", "output": "Route data available (details in route_data)"})
            
            # 5. Guardian Response
            yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'guardian', 'status': 'processing', 'progress': 30, 'message': '回答を生成中...'})}\n\n".encode('utf-8')
            
            guardian_response = guardian.generate_response(
                urgency=current_urgency,
                plan_details={
                    "origin": origin,
                    "destination": destination,
                    "sentinel_instruction": sentinel_plan.get("instruction_to_agent"),
                    "route_found": route_result is not None,
                    "route_summary": route_result.get("risk_assessment") if route_result else None
                }
            )
            trace_log.append({"agent": "Guardian", "output": guardian_response})
            print(f"[DEBUG] Guardian Response: {guardian_response}", flush=True)
            
            yield f"data: {json.dumps({'type': 'agent_status', 'agent': 'guardian', 'status': 'complete', 'progress': 100, 'message': '完了'})}\n\n".encode('utf-8')
            
            # 6. Final Result
            # guardian_responseは辞書なので、textフィールドを抽出
            narrative_text = guardian_response.get('text', str(guardian_response)) if isinstance(guardian_response, dict) else str(guardian_response)
            
            final_result = {
                "type": "result",
                "data": {
                    "status": "success",
                    "ui_view": "MAP_WITH_RISK" if route_result else "CHAT_ONLY",
                    "narrative": narrative_text,
                    "route_data": route_result,
                    "alert_info": alert_info,
                    "trace_log": trace_log
                }
            }
            yield f"data: {json.dumps(final_result)}\n\n".encode('utf-8')
            print(f"🟢 === [SUCCESS] SSE Stream Completed ===\n", flush=True)
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            yield f"data: {json.dumps({'type': 'error', 'message': str(e)})}\n\n".encode('utf-8')
    
    return Response(
        generate(),
        mimetype='text/event-stream',
        direct_passthrough=True,
        headers={
            'Cache-Control': 'no-cache',
            'X-Accel-Buffering': 'no',
            'Connection': 'keep-alive',
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'text/event-stream; charset=utf-8'
        }
    )

@functions_framework.http
def handle_reverse_geocode(request):
    """
    GET /reverseGeocode?lat=...&lng=...
    施設の正確な名前を取得する (Places API via GeocodeService)
    """
    try:
        # Flask request.args
        lat = request.args.get('lat', type=float)
        lng = request.args.get('lng', type=float)
        
        if lat is None or lng is None:
             return jsonify({"error": "Missing lat/lng"}), 400
             
        if not geocode_service:
             return jsonify({"error": "Geocode service disabled"}), 503
             
        # 1. Try POI Name (Places API) - Precise
        poi_data = geocode_service.get_poi_name(lat, lng)
        if poi_data:
             # poi_data is {"name": "...", "lat": ..., "lng": ...}
             return jsonify({
                 "name": poi_data["name"], 
                 "type": "POI", 
                 "lat": poi_data["lat"], 
                 "lng": poi_data["lng"]
             })
             
        # 2. Try Municipality (Standard Geo) - Fallback

        muni = geocode_service.get_municipality(lat, lng)
        if muni:
             return jsonify({"name": muni, "type": "MUNICIPALITY"})
             
        return jsonify({"name": "選択した地点", "type": "UNKNOWN"})
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# Local Testing Block
if __name__ == "__main__":
    # ローカルで python main.py した時の動作確認用
    # functions_framework ではなく生のFlaskを使ってバッファリング問題を回避する
    from flask import Flask, request
    print("Starting Raw Flask server for local testing (No buffering)...")
    
    app = Flask(__name__)
    
    @app.route("/findSafeRoute", methods=["POST"])
    def route_normal():
        return handle_route_request(request)
        
    @app.route("/findSafeRouteStream", methods=["POST"])
    def route_stream():
        return handle_route_request_stream(request)
        
    @app.route("/reverseGeocode", methods=["GET"])
    def route_reverse_geocode():
        return handle_reverse_geocode(request)
        
    # debug=True, threaded=True でストリーミングをサポート
    # Cloud Run対応: PORT環境変数から取得
    port = int(os.environ.get("PORT", 8080))
    app.run(host="0.0.0.0", port=port, debug=False, threaded=True)
