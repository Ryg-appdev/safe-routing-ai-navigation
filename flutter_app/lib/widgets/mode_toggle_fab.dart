import 'package:flutter/material.dart';

/// モード切替FAB（Floating Action Button）
class ModeToggleFab extends StatelessWidget {
  final bool isEmergency;
  final VoidCallback onPressed;
  final AnimationController pulseAnimation;
  
  const ModeToggleFab({
    super.key,
    required this.isEmergency,
    required this.onPressed,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        final scale = isEmergency 
          ? 1.0 + (pulseAnimation.value * 0.1)
          : 1.0;
        
        return Transform.scale(
          scale: scale,
          child: FloatingActionButton.large(
            onPressed: onPressed,
            backgroundColor: isEmergency 
              ? Colors.red 
              : Colors.blue,
            foregroundColor: Colors.white,
            elevation: 8,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                isEmergency ? Icons.warning_rounded : Icons.wb_sunny,
                key: ValueKey(isEmergency),
                size: 36,
              ),
            ),
          ),
        );
      },
    );
  }
}
