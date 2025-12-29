import 'package:flutter/material.dart';

/// 分析ポイント詳細シート
/// ルート上の分析ポイントをタップした際に表示される
class AnalysisPointDetailSheet extends StatelessWidget {
  final double lat;
  final double lng;
  final double score;
  final List<String> risks;

  const AnalysisPointDetailSheet({
    super.key,
    required this.lat,
    required this.lng,
    required this.score,
    required this.risks,
  });

  /// スコアに応じた色を返す
  Color _getScoreColor() {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  /// スコアに応じたラベルを返す
  String _getScoreLabel() {
    if (score >= 80) return '安全';
    if (score >= 60) return '注意';
    return '危険';
  }

  /// リスク文字列を日本語で分かりやすく変換
  String _translateRisk(String risk) {
    if (risk.startsWith('FLOOD_RISK:')) {
      return '🌊 低地のため浸水リスクがあります';
    }
    if (risk.startsWith('VIBE_RISK:')) {
      final atmosphere = risk.replaceFirst('VIBE_RISK:', '').trim();
      return '👁️ 雰囲気: $atmosphere';
    }
    if (risk.startsWith('SHADOW_RISK:')) {
      return '🌙 夜間は暗い通りです';
    }
    if (risk.startsWith('SAFETY_BONUS:')) {
      final detail = risk.replaceFirst('SAFETY_BONUS:', '').trim();
      return '✅ 安全スポット: $detail';
    }
    // その他のリスク
    return '⚠️ $risk';
  }

  /// リスクがプラス要因（ボーナス）かどうか
  bool _isBonus(String risk) {
    return risk.startsWith('SAFETY_BONUS:');
  }

  @override
  Widget build(BuildContext context) {
    // リスク要因とボーナス要因を分離
    final riskItems = risks.where((r) => !_isBonus(r)).toList();
    final bonusItems = risks.where((r) => _isBonus(r)).toList();

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

          // ヘッダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                // スコア表示 (円グラフ風プログレスリング)
                SizedBox(
                  width: 60,
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 背景のリング (グレー)
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: 1.0,
                          strokeWidth: 4,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.grey.shade200,
                          ),
                        ),
                      ),
                      // スコアのリング (色付き)
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: score / 100,
                          strokeWidth: 4,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getScoreColor(),
                          ),
                        ),
                      ),
                      // 中央のスコア数値
                      Text(
                        score.toInt().toString(),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _getScoreColor(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // タイトル
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '安全スコア: ${_getScoreLabel()}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
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
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // リスク要因リスト
          if (riskItems.isNotEmpty || bonusItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // リスク要因
                  ...riskItems.map((risk) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _translateRisk(risk),
                      style: const TextStyle(fontSize: 14),
                    ),
                  )),
                  // ボーナス要因
                  ...bonusItems.map((risk) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _translateRisk(risk),
                      style: TextStyle(fontSize: 14, color: Colors.green[700]),
                    ),
                  )),
                ],
              ),
            ),

          // リスクがない場合
          if (riskItems.isEmpty && bonusItems.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '✅ 特にリスク要因はありません',
                style: TextStyle(fontSize: 14, color: Colors.green[700]),
              ),
            ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

/// 分析ポイント詳細シートを表示
void showAnalysisPointDetailSheet({
  required BuildContext context,
  required double lat,
  required double lng,
  required double score,
  required List<String> risks,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => AnalysisPointDetailSheet(
      lat: lat,
      lng: lng,
      score: score,
      risks: risks,
    ),
  );
}
