import 'package:flutter/material.dart';

/// 警報ステータスバナー
/// 警報あり: 赤背景 + 警報名
/// 警報なし: 緑/グレー背景 + "警報なし"
class AlertStatusBanner extends StatelessWidget {
  final Map<String, dynamic>? alertInfo;
  final VoidCallback? onTap;
  final bool isCompact;

  const AlertStatusBanner({
    super.key,
    this.alertInfo,
    this.onTap,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasAlert = alertInfo != null && alertInfo!['type'] != 'NONE';
    final title = alertInfo?['title'] ?? (hasAlert ? '警報発令中' : '警報・注意報なし');
    final level = alertInfo?['level'] ?? 'none';
    
    // アイコンの決定（Material Icons使用）
    IconData iconData;
    if (level == 'critical') {
      iconData = Icons.warning_amber_rounded;
    } else if (level == 'warning') {
      iconData = Icons.error_outline_rounded;
    } else if (level == 'advisory') {
      iconData = Icons.info_outline_rounded;
    } else {
      iconData = Icons.check_circle_outline_rounded;
    }
    
    // 背景色の決定
    Color backgroundColor;
    Color textColor = Colors.white;
    
    if (level == 'critical') {
      backgroundColor = Colors.red.shade700;
    } else if (level == 'warning') {
      backgroundColor = Colors.orange.shade700;
    } else if (level == 'advisory') {
      backgroundColor = Colors.amber.shade700;
      textColor = Colors.black87;
    } else {
      backgroundColor = Colors.green.shade600;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 14,
          vertical: isCompact ? 6 : 10,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              iconData,
              color: textColor,
              size: isCompact ? 16 : 18,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: isCompact ? 11 : 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              color: textColor.withOpacity(0.8),
              size: isCompact ? 16 : 18,
            ),
          ],
        ),
      ),
    );
  }
}
