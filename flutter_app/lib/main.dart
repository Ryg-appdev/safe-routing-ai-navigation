import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/map_screen.dart';
import 'providers/theme_provider.dart';

void main() {
  runApp(const ProviderScope(child: SafeRoutingApp()));
}

class SafeRoutingApp extends ConsumerWidget {
  const SafeRoutingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEmergencyMode = ref.watch(emergencyModeProvider);
    
    return MaterialApp(
      title: 'Safe Routing AI',
      debugShowCheckedModeBanner: false,
      theme: isEmergencyMode ? _emergencyTheme : _normalTheme,
      home: const MapScreen(),
    );
  }
  
  // 日常モード: 青ベース
  static final _normalTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF007AFF),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: Colors.white,
  );
  
  // 非常時モード: 赤＋ダーク
  static final _emergencyTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF3B30),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF1C1C1E),
  );
}
