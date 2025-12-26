import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';

/// Thinking Log オーバーレイ（ターミナル風）
class ThinkingLogOverlay extends ConsumerWidget {
  const ThinkingLogOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(thinkingLogProvider);
    
    if (logs.isEmpty) return const SizedBox.shrink();
    
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.green.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: ListView.builder(
        reverse: true,
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final log = logs[logs.length - 1 - index];
          final isWarning = log.contains('⚠️') || log.contains('DANGEROUS');
          final isSuccess = log.contains('SAFE') || log.contains('selected');
          
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              log,
              style: TextStyle(
                fontFamily: 'RobotoMono',
                fontSize: 12,
                color: isWarning 
                  ? Colors.orange
                  : isSuccess
                    ? Colors.lightGreenAccent
                    : Colors.greenAccent,
              ),
            ),
          );
        },
      ),
    );
  }
}
