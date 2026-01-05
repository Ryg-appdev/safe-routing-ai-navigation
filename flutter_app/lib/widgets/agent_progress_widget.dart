import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// エージェント進捗表示ウィジェット（フェイク進捗付き）
class AgentProgressWidget extends StatefulWidget {
  final Map<String, AgentStatus> agentStatuses;

  const AgentProgressWidget({
    super.key,
    required this.agentStatuses,
  });

  @override
  State<AgentProgressWidget> createState() => _AgentProgressWidgetState();
}

class _AgentProgressWidgetState extends State<AgentProgressWidget> {
  // 表示用の進捗値（フェイク進捗含む）
  Map<String, int> _displayProgress = {};
  Timer? _fakeProgressTimer;

  @override
  void initState() {
    super.initState();
    _startFakeProgressTimer();
  }

  @override
  void dispose() {
    _fakeProgressTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(AgentProgressWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 実際の進捗が来たら表示値を更新
    for (final entry in widget.agentStatuses.entries) {
      final key = entry.key;
      final actualProgress = entry.value.progress;
      final currentDisplay = _displayProgress[key] ?? 0;
      
      // 実際の進捗が表示値より大きい場合は更新
      if (actualProgress > currentDisplay) {
        _displayProgress[key] = actualProgress;
      }
    }
  }

  void _startFakeProgressTimer() {
    _fakeProgressTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) return;
      
      bool needsUpdate = false;
      
      for (final entry in widget.agentStatuses.entries) {
        final key = entry.key;
        final status = entry.value;
        
        // 処理中のエージェントのみフェイク進捗
        if (status.status == 'processing') {
          final actualProgress = status.progress;
          final currentDisplay = _displayProgress[key] ?? actualProgress;
          
          // 上限: 実際の進捗 + 40%（ただし95%まで）
          final ceiling = (actualProgress + 40).clamp(0, 95);
          
          if (currentDisplay < ceiling) {
            _displayProgress[key] = currentDisplay + 1;
            needsUpdate = true;
          }
        }
      }
      
      if (needsUpdate) {
        setState(() {});
      }
    });
  }

  int _getDisplayProgress(String key) {
    final status = widget.agentStatuses[key];
    if (status == null) return 0;
    
    // 完了の場合は実際の値（100）を返す
    if (status.status == 'complete') {
      return status.progress;
    }
    
    // 処理中の場合はフェイク進捗を返す
    return _displayProgress[key] ?? status.progress;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAgentRow('sentinel', Icons.psychology, '状況判断'),
          const SizedBox(height: 12),
          _buildAgentRow('navigator', Icons.explore, 'ルート探索'),
          const SizedBox(height: 12),
          _buildAgentRow('analyst', Icons.visibility, 'リスク分析'),
          const SizedBox(height: 12),
          _buildAgentRow('guardian', Icons.shield, '案内役'),
        ],
      ),
    );
  }

  Widget _buildAgentRow(String key, IconData icon, String name) {
    final status = widget.agentStatuses[key] ?? AgentStatus.waiting();
    final isActive = status.status == 'processing';
    final isComplete = status.status == 'complete';
    final color = isActive
        ? Colors.blue
        : (isComplete ? Colors.green : Colors.grey.shade600);
    
    final displayProgress = _getDisplayProgress(key);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 上段: アイコン + 名前 + ステータス + メッセージ + ％
        Row(
          children: [
            SizedBox(
              width: 20,
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            SizedBox(
              width: 20,
              child: Center(child: _buildStatusIcon(status.status)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status.message.isNotEmpty ? status.message : (status.status == 'waiting' ? '待機中...' : ''),
                style: TextStyle(
                  fontSize: 10,
                  color: isActive ? Colors.blue : Colors.grey.shade600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 35,
              child: Text(
                '$displayProgress%',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // 下段: プログレスバー
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: displayProgress / 100),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isComplete ? Colors.green : Colors.blue,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatusIcon(String status) {
    switch (status) {
      case 'complete':
        return const Icon(Icons.check_circle, size: 14, color: Colors.green);
      case 'processing':
        return const CupertinoActivityIndicator(radius: 7);
      default:
        return Icon(Icons.schedule, size: 14, color: Colors.grey.shade500);
    }
  }
}

class AgentStatus {
  final String status;
  final int progress;
  final String message;

  AgentStatus({
    required this.status,
    required this.progress,
    required this.message,
  });

  factory AgentStatus.waiting() {
    return AgentStatus(status: 'waiting', progress: 0, message: '');
  }

  factory AgentStatus.fromJson(Map<String, dynamic> json) {
    return AgentStatus(
      status: json['status'] ?? 'waiting',
      progress: json['progress'] ?? 0,
      message: json['message'] ?? '',
    );
  }
}
