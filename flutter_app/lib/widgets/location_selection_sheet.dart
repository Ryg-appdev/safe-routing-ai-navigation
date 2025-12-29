import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// 地点選択シート
/// 地図タップ時に表示されるボトムシート
class LocationSelectionSheet extends StatelessWidget {
  final LatLng position;
  final String? placeName;
  final VoidCallback onSetAsOrigin;
  final VoidCallback onSetAsDestination;
  final VoidCallback? onClose;

  const LocationSelectionSheet({
    super.key,
    required this.position,
    this.placeName,
    required this.onSetAsOrigin,
    required this.onSetAsDestination,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
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
          
          // 地点情報
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                // ピンアイコン
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.place,
                    color: Colors.red.shade600,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                // 地点名と座標
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        placeName ?? '選択した地点',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // 閉じるボタン
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey[500]),
                  onPressed: onClose ?? () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // アクションボタン
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // 出発地に設定
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      onSetAsOrigin();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.trip_origin, size: 18),
                    label: const Text('出発地に設定'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 目的地に設定
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      onSetAsDestination();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.flag, size: 18),
                    label: const Text('目的地に設定'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

/// 地点選択シートを表示
void showLocationSelectionSheet({
  required BuildContext context,
  required LatLng position,
  String? placeName,
  required VoidCallback onSetAsOrigin,
  required VoidCallback onSetAsDestination,
  VoidCallback? onDismiss,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => LocationSelectionSheet(
      position: position,
      placeName: placeName,
      onSetAsOrigin: onSetAsOrigin,
      onSetAsDestination: onSetAsDestination,
    ),
  ).whenComplete(() {
    // シートが閉じられたら（キャンセル含む）コールバックを呼ぶ
    onDismiss?.call();
  });
}
