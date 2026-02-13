import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  // Development: localhost (Simulator/Emulator経由)
  // Production: Cloud Run URL
  static const String _devUrl = 'http://127.0.0.1:8080';
  static const String _prodUrl = 'https://safe-routing-api-20596701846.asia-northeast1.run.app';
  
  // kDebugModeでDev/Prod切り替え（Release buildは本番URLを使用）
  static String get _baseUrl => kDebugMode ? _devUrl : _prodUrl;

  Future<Map<String, dynamic>> findSafeRoute(String origin, String destination) async {
    final url = Uri.parse('$_baseUrl/findSafeRoute');
    
    // Test payload
    final body = jsonEncode({
      "origin": origin,
      "destination": destination,
      "context": {
        "mode": "NORMAL",
        "weather_condition": "Clear",
        "temperature": 20.0
      }
    });

    try {
      print("[API] POST $url");
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      if (response.statusCode == 200) {
        print("[API] Success: ${response.body}");
        return jsonDecode(response.body);
      } else {
        print("[API] Error: ${response.statusCode} ${response.body}");
        throw Exception('Failed to load route: ${response.statusCode}');
      }
    } catch (e) {
      print("[API] Exception: $e");
      rethrow;
    }
  }
  
  /// SSE ストリーミング版ルート検索
  /// リアルタイムでエージェントの処理状況を受け取る
  /// testAlert: テスト用警報（設定画面から指定された場合）
  Stream<Map<String, dynamic>> findSafeRouteStream(
    String origin, 
    String destination, 
    {String? testAlert}
  ) async* {
    final url = Uri.parse('$_baseUrl/findSafeRouteStream');
    
    final requestBody = {
      "origin": origin,
      "destination": destination,
      "context": {
        "mode": "NORMAL",
        "weather_condition": "Clear",
        "temperature": 20.0
      }
    };
    
    // テスト警報が設定されている場合、リクエストに含める
    if (testAlert != null) {
      requestBody["test_alert"] = testAlert;
    }
    
    final body = jsonEncode(requestBody);

    try {
      print("[API SSE] POST $url");
      final request = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream'
        ..body = body;
      
      final client = http.Client();
      final streamedResponse = await client.send(request);
      
      if (streamedResponse.statusCode == 200) {
        String buffer = '';
        
        await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
          buffer += chunk;
          
            // 行単位で処理（より堅牢なアプローチ）
            while (buffer.contains('\n')) {
              final lineEnd = buffer.indexOf('\n');
              final line = buffer.substring(0, lineEnd).trim();
              buffer = buffer.substring(lineEnd + 1);
              
              if (line.isEmpty) continue; // 空行はスキップ
              
              if (line.startsWith('data:')) {
                // "data:" の後のJSON部分を取得
                final jsonStr = line.substring(5).trim();
                if (jsonStr.isEmpty) continue;
                
                try {
                  final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;
                  yield parsed;
                } catch (e) {
                  print("[API SSE] Parse error: $e");
                }
              }
            }
        }
        
        client.close();
      } else {
        throw Exception('SSE failed: ${streamedResponse.statusCode}');
      }
    } catch (e) {
      print("[API SSE] Exception: $e");
      rethrow;
    }
  }
  
  /// 逆ジオコーディング (Backend Places API)
  /// Returns: { "name": "...", "lat": 35.1, "lng": 139.1, "type": "POI" } or null
  Future<Map<String, dynamic>?> getReverseGeocode(double lat, double lng) async {
    final url = Uri.parse('$_baseUrl/reverseGeocode?lat=$lat&lng=$lng');
    try {
      print("[API] GET $url");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("[API] Geo Success: ${data['name']} (${data['type']})");
        return data as Map<String, dynamic>;
      }
    } catch (e) {
      print("[API] Geo Error: $e");
    }
    return null;
  }
  /// 最寄りの避難所を検索
  /// disasterType: 災害種別（"洪水", "津波", "高潮" など）
  /// Returns: { "shelters": [...], "count": N }
  Future<List<Map<String, dynamic>>> findNearestShelters(
    double lat, 
    double lng, 
    {int limit = 3, String? disasterType}
  ) async {
    var urlStr = '$_baseUrl/findNearestShelters?lat=$lat&lng=$lng&limit=$limit';
    if (disasterType != null) {
      urlStr += '&disaster_type=${Uri.encodeComponent(disasterType)}';
    }
    final url = Uri.parse(urlStr);
    try {
      print("[API] GET $url");
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final shelters = (data['shelters'] as List)
            .map((s) => s as Map<String, dynamic>)
            .toList();
        print("[API] Found ${shelters.length} shelters (type: $disasterType)");
        return shelters;
      }
    } catch (e) {
      print("[API] Shelter Error: $e");
    }
    return [];
  }
}
