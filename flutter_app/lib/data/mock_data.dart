import 'package:google_maps_flutter/google_maps_flutter.dart';

/// モックルートデータ
class MockData {
  // 渋谷駅周辺のテスト座標
  static const LatLng shibuyaStation = LatLng(35.6580, 139.7016);
  static const LatLng destination = LatLng(35.6614, 139.6930); // 代々木公園方面
  
  // 浸水危険エリア（モック）
  static final List<LatLng> floodZone = [
    const LatLng(35.6595, 139.6980),
    const LatLng(35.6610, 139.6970),
    const LatLng(35.6620, 139.6990),
    const LatLng(35.6605, 139.7010),
  ];
  
  // 通常ルート（危険エリア通過）
  static final List<LatLng> unsafeRoute = [
    shibuyaStation,
    const LatLng(35.6590, 139.6990),
    const LatLng(35.6605, 139.6975), // 浸水エリア通過
    destination,
  ];
  
  // 安全ルート（高台経由）
  static final List<LatLng> safeRoute = [
    shibuyaStation,
    const LatLng(35.6570, 139.6950), // 南へ迂回
    const LatLng(35.6580, 139.6900), // 高台エリア
    const LatLng(35.6600, 139.6890),
    destination,
  ];
  
  // AIナレーション（モック）
  static const String normalModeNarration = 
    "お疲れ様です。今日は少し遅いので、人通りの多い明るい道を案内しますね。";
  
  static const String emergencyModeNarration = 
    "警告。前方に浸水エリアを検知。高台経由のルートに変更しました。直ちに移動を開始してください。";
}
