import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 非常時モードの状態管理
class EmergencyModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  void toggle() {
    state = !state;
  }
  
  void set(bool value) {
    state = value;
  }
}

final emergencyModeProvider = NotifierProvider<EmergencyModeNotifier, bool>(
  EmergencyModeNotifier.new,
);

/// Thinking Log の状態管理
class ThinkingLogNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];
  
  void add(String log) {
    state = [...state, log];
  }
  
  void clear() {
    state = [];
  }
}

final thinkingLogProvider = NotifierProvider<ThinkingLogNotifier, List<String>>(
  ThinkingLogNotifier.new,
);
