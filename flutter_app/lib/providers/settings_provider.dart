import 'package:flutter_riverpod/flutter_riverpod.dart';

/// テスト用警報の状態管理
class TestAlertNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  
  void set(String? value) {
    state = value;
  }
  
  void clear() {
    state = null;
  }
}

final testAlertProvider = NotifierProvider<TestAlertNotifier, String?>(
  TestAlertNotifier.new,
);

/// 利用可能なテスト警報タイプ
const List<String> availableTestAlerts = [
  '大雨警報',
  '洪水警報',
  '津波警報',
  '津波注意報',
  '土砂災害警戒情報',
  '地震情報',
  '高潮警報',
];

/// API から取得した実際の警報情報を保持
class RealAlertNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;
  
  void set(Map<String, dynamic>? value) {
    state = value;
  }
  
  void clear() {
    state = null;
  }
}

final realAlertProvider = NotifierProvider<RealAlertNotifier, Map<String, dynamic>?>(
  RealAlertNotifier.new,
);

/// 有効な警報（テスト警報優先）
/// テスト警報が設定されていればスタブを使用、なければ実際の警報を使用
final effectiveAlertProvider = Provider<Map<String, dynamic>?>((ref) {
  final testAlert = ref.watch(testAlertProvider);
  final realAlert = ref.watch(realAlertProvider);
  
  if (testAlert != null) {
    // テスト警報が設定されている場合、実際のAPIと同じ形式のスタブを返す
    return alertStubs[testAlert];
  }
  
  return realAlert;
});

/// 警報スタブデータ（実際のAPIレスポンスと同じ形式）
/// バックエンドの disaster_alert_service が返す形式に準拠
const Map<String, Map<String, dynamic>> alertStubs = {
  '大雨警報': {
    'type': 'RAIN',
    'level': 'warning',
    'title': '大雨警報',
    'message': '大雨警報が発令されています。低地への移動にご注意ください。',
    'icon': '🌧️',
    'should_emergency_mode': true,
  },
  '洪水警報': {
    'type': 'FLOOD',
    'level': 'warning',
    'title': '洪水警報',
    'message': '洪水警報が発令されています。河川の近くにはご注意ください。',
    'icon': '🌊',
    'should_emergency_mode': true,
  },
  '津波警報': {
    'type': 'TSUNAMI',
    'level': 'critical',
    'title': '津波警報',
    'message': '津波警報が発令されています。直ちに高台へ避難してください。',
    'icon': '🌊',
    'should_emergency_mode': true,
  },
  '津波注意報': {
    'type': 'TSUNAMI',
    'level': 'advisory',
    'title': '津波注意報',
    'message': '津波注意報が発令されています。海岸から離れてください。',
    'icon': '🌊',
    'should_emergency_mode': true,
  },
  '土砂災害警戒情報': {
    'type': 'LANDSLIDE',
    'level': 'warning',
    'title': '土砂災害警戒情報',
    'message': '土砂災害警戒情報が発令されています。山沿いを避けてください。',
    'icon': '⛰️',
    'should_emergency_mode': true,
  },
  '地震情報': {
    'type': 'EARTHQUAKE',
    'level': 'critical',
    'title': '地震情報',
    'message': '地震が発生しました。広い道を優先し、倒壊リスクのある建物を避けてください。',
    'icon': '🔴',
    'should_emergency_mode': true,
  },
  '高潮警報': {
    'type': 'STORM_SURGE',
    'level': 'warning',
    'title': '高潮警報',
    'message': '高潮警報が発令されています。沿岸部から離れてください。',
    'icon': '🌊',
    'should_emergency_mode': true,
  },
};
