import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';

/// Thinking Log オーバーレイ（ターミナル風）
class ThinkingLogOverlay extends ConsumerStatefulWidget {
  const ThinkingLogOverlay({super.key});

  @override
  ConsumerState<ThinkingLogOverlay> createState() => _ThinkingLogOverlayState();
}

class _ThinkingLogOverlayState extends ConsumerState<ThinkingLogOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  final ScrollController _scrollController = ScrollController();
  
  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }
  
  @override
  void dispose() {
    _blinkController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(thinkingLogProvider);
    
    if (logs.isEmpty) return const SizedBox.shrink();
    
    // ログが更新されたら自動スクロール
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
    
    return Container(
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.green.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ログ一覧
            ...logs.map((log) {
              final isSuccess = log.contains('完了') || log.contains('スコア');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  log,
                  style: TextStyle(
                    fontFamily: 'RobotoMono',
                    fontSize: 12,
                    color: isSuccess ? Colors.lightGreenAccent : Colors.greenAccent,
                  ),
                ),
              );
            }),
            // 処理中インジケータ
            AnimatedBuilder(
              animation: _blinkController,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.4 + (_blinkController.value * 0.6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      '> 処理中...',
                      style: TextStyle(
                        fontFamily: 'RobotoMono',
                        fontSize: 12,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
