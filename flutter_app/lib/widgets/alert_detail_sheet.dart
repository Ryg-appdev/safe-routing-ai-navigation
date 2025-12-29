import 'package:flutter/material.dart';

/// 警報詳細シート
/// 全警報種別の一覧表示
class AlertDetailSheet extends StatelessWidget {
  final Map<String, dynamic>? alertInfo;
  final VoidCallback? onClose;

  const AlertDetailSheet({
    super.key,
    this.alertInfo,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ハンドル
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // ヘッダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange.shade700,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Text(
                  '現在の警報・注意報',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose ?? () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // 警報リスト
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildAlertRow(
                  icon: Icons.water_drop_outlined,
                  iconColor: Colors.blue,
                  title: '大雨警報',
                  isActive: _isAlertActive('RAIN', '大雨警報'),
                ),
                _buildAlertRow(
                  icon: Icons.waves_outlined,
                  iconColor: Colors.blue.shade700,
                  title: '洪水警報',
                  isActive: _isAlertActive('FLOOD', '洪水警報'),
                ),
                _buildAlertRow(
                  icon: Icons.crisis_alert,
                  iconColor: Colors.red,
                  title: '地震情報',
                  isActive: _isAlertActive('EARTHQUAKE', '地震情報'),
                ),
                _buildAlertRow(
                  icon: Icons.tsunami_outlined,
                  iconColor: Colors.indigo,
                  title: '津波警報',
                  isActive: _isAlertActive('TSUNAMI', '津波警報') || _isAlertActive('TSUNAMI', '津波注意報'),
                ),
                _buildAlertRow(
                  icon: Icons.landscape_outlined,
                  iconColor: Colors.brown,
                  title: '土砂災害警戒情報',
                  isActive: _isAlertActive('LANDSLIDE', '土砂災害警戒情報'),
                ),
              ],
            ),
          ),
          
          // アクティブな警報がある場合はメッセージ表示
          if (alertInfo != null && alertInfo!['type'] != 'NONE')
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    _getAlertIcon(alertInfo!['type']),
                    color: Colors.red.shade700,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      alertInfo!['message'] ?? '',
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
  
  /// 警報がアクティブかチェック
  bool _isAlertActive(String type, String title) {
    if (alertInfo == null) return false;
    return alertInfo!['type'] == type;
  }
  
  IconData _getAlertIcon(String? type) {
    switch (type) {
      case 'RAIN':
        return Icons.water_drop;
      case 'FLOOD':
        return Icons.waves;
      case 'EARTHQUAKE':
        return Icons.vibration_rounded;
      case 'TSUNAMI':
        return Icons.tsunami;
      case 'LANDSLIDE':
        return Icons.landscape;
      default:
        return Icons.warning_amber_rounded;
    }
  }
  
  Widget _buildAlertRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required bool isActive,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: isActive ? iconColor : Colors.grey[400],
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: isActive ? Colors.red.shade700 : Colors.grey[700],
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? Colors.red : Colors.green,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              isActive ? '発令中' : 'なし',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 警報詳細シートを表示
void showAlertDetailSheet(BuildContext context, Map<String, dynamic>? alertInfo) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => AlertDetailSheet(alertInfo: alertInfo),
  );
}
