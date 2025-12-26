import 'package:flutter/material.dart';

/// AIナレーション表示のBottomSheet
class NarrativeBottomSheet extends StatelessWidget {
  final String narrative;
  final bool isEmergency;
  
  const NarrativeBottomSheet({
    super.key,
    required this.narrative,
    required this.isEmergency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
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
          // ハンドル
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
          const SizedBox(height: 16),
          
          // AIアイコン + タイトル
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
              Text(
                isEmergency ? 'Emergency AI' : 'Concierge AI',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isEmergency ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // ナレーションテキスト
          Text(
            narrative,
            style: TextStyle(
              fontSize: 16,
              height: 1.5,
              color: isEmergency ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          
          // アクションボタン
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: isEmergency ? Colors.red : Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isEmergency ? '今すぐ移動開始' : 'ナビを開始',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
