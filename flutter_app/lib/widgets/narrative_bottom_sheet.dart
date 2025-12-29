import 'package:flutter/material.dart';

/// AIナレーション表示のBottomSheet（ドラッグで収納可能、ボタンなし）
class NarrativeBottomSheet extends StatefulWidget {
  final String narrative;
  final bool isEmergency;
  
  const NarrativeBottomSheet({
    super.key,
    required this.narrative,
    required this.isEmergency,
  });

  @override
  State<NarrativeBottomSheet> createState() => _NarrativeBottomSheetState();
}

class _NarrativeBottomSheetState extends State<NarrativeBottomSheet> {
  // シートの高さ状態（0.0 = 収納、1.0 = 展開）
  double _sheetPosition = 1.0;
  
  // 展開時のコンテンツ高さ（概算）
  static const double _expandedContentHeight = 120.0;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      // 下にドラッグで収納、上にドラッグで展開
      _sheetPosition -= details.delta.dy / _expandedContentHeight;
      _sheetPosition = _sheetPosition.clamp(0.0, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    // スナップ: 0.5より大きければ展開、小さければ収納
    final targetPosition = _sheetPosition > 0.5 ? 1.0 : 0.0;
    
    setState(() {
      _sheetPosition = targetPosition;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEmergency = widget.isEmergency;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: bottomPadding + 12,
        ),
        decoration: BoxDecoration(
          color: isEmergency 
            ? const Color(0xFF2C2C2E)
            : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ハンドルバー
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isEmergency ? Colors.grey.shade600 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // AIアイコン + タイトル（常に表示）
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isEmergency 
                      ? Colors.red.withOpacity(0.2)
                      : Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.smart_toy,
                    color: isEmergency ? Colors.red : Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isEmergency ? 'Emergency AI' : 'Concierge AI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isEmergency ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            
            // 展開部分（アニメーション付き）
            ClipRect(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                heightFactor: _sheetPosition,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    
                    // ナレーションテキスト
                    Text(
                      widget.narrative,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: isEmergency ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
