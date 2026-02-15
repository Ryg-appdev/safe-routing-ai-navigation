import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

/// 設定画面
/// ライセンス、帰属表示、AI免責事項を表示
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testAlert = ref.watch(testAlertProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          // テスト用設定（デバッグ用）
          _buildSectionHeader('テスト用設定（開発者向け）'),
          _buildTestAlertTile(context, ref, testAlert),
          
          const Divider(height: 32),
          
          // 使用サービス・データソース
          _buildSectionHeader('使用サービス・データソース'),
          _buildServiceTile(
            icon: Icons.map,
            title: 'Google Maps Platform',
            subtitle: 'Maps SDK, Routes API, Geocoding API',
            url: 'https://cloud.google.com/maps-platform',
          ),
          _buildServiceTile(
            icon: Icons.auto_awesome,
            title: 'Google Cloud / Gemini API',
            subtitle: 'Gemini 3 Pro / Flashによるマルチエージェント',
            url: 'https://ai.google.dev/',
          ),
          _buildServiceTile(
            icon: Icons.cloud,
            title: '気象庁',
            subtitle: '防災気象情報',
            url: 'https://www.jma.go.jp/bosai/',
          ),
          _buildServiceTile(
            icon: Icons.warning_amber,
            title: '国土交通省',
            subtitle: 'ハザードマップポータルサイト',
            url: 'https://disaportal.gsi.go.jp/',
          ),
          
          const Divider(height: 32),
          
          // OSSライセンス
          _buildSectionHeader('法的情報'),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('OSSライセンス'),
            subtitle: const Text('使用しているオープンソースソフトウェア'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // Flutter標準のLicensePageを表示
              showLicensePage(
                context: context,
                applicationName: 'Safe Routing AI',
                applicationVersion: '1.0.0',
                applicationLegalese: '© 2024 Safe Routing AI Team',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('AI免責事項'),
            subtitle: const Text('ご利用上の注意'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showDisclaimerDialog(context),
          ),
          
          const Divider(height: 32),
          
          // アプリ情報
          _buildSectionHeader('アプリ情報'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('バージョン'),
            subtitle: Text('1.0.0'),
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
  
  /// テスト用警報設定タイル
  Widget _buildTestAlertTile(BuildContext context, WidgetRef ref, String? testAlert) {
    return ListTile(
      leading: Icon(
        Icons.bug_report,
        color: testAlert != null ? Colors.orange : Colors.grey,
      ),
      title: const Text('テスト用警報'),
      subtitle: Text(testAlert ?? '無効（実際のAPIを使用）'),
      trailing: PopupMenuButton<String?>(
        icon: const Icon(Icons.chevron_right),
        onSelected: (value) {
          ref.read(testAlertProvider.notifier).set(value);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(value != null 
                ? 'テスト警報を「$value」に設定しました' 
                : 'テスト警報を無効にしました'),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        itemBuilder: (context) => [
          const PopupMenuItem<String?>(
            value: null,
            child: Row(
              children: [
                Icon(Icons.close, color: Colors.grey),
                SizedBox(width: 8),
                Text('無効（実際のAPIを使用）'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          ...availableTestAlerts.map((alert) => PopupMenuItem<String?>(
            value: alert,
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Text(alert),
              ],
            ),
          )),
        ],
      ),
    );
  }
  
  /// セクションヘッダー
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
  
  /// サービス・データソースのタイル
  Widget _buildServiceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title),
      subtitle: Text(subtitle),
      // URLは表示のみ（タップでWebページを開く機能は省略）
    );
  }
  
  /// AI免責事項ダイアログ
  void _showDisclaimerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 8),
            Text('AI免責事項'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            '【ご注意】\n\n'
            '本アプリのルート案内はAI（人工知能）による参考情報です。\n\n'
            '非常時・避難時の最終的な判断は、公式の避難情報や自治体の指示に従ってください。\n\n'
            '本アプリの案内に従った結果生じた損害について、開発者は責任を負いかねます。\n\n'
            '常に周囲の状況を確認し、安全を最優先にしてください。',
            style: TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
}
