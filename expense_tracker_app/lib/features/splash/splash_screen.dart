import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';

/// Shown the instant the Flutter engine attaches, replacing the native
/// static splash — this is where the actual motion/brand moment lives,
/// since native splash screens can't animate. Runs for however long
/// [_AppBootstrapState._bootstrap] takes to load everything.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                  width: 128,
                  height: 128,
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.55),
                        blurRadius: 44,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: AppColors.expense.withValues(alpha: 0.35),
                        blurRadius: 60,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    fit: BoxFit.contain,
                  ),
                )
                .animate()
                .scale(
                  begin: const Offset(0.4, 0.4),
                  end: const Offset(1, 1),
                  duration: 550.ms,
                  curve: Curves.easeOutBack,
                )
                .fadeIn(duration: 350.ms)
                .then()
                .shimmer(duration: 1200.ms, color: Colors.white70),
            const SizedBox(height: 28),
            const Text(
                  'Spendo',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                )
                .animate(delay: 200.ms)
                .fadeIn(duration: 400.ms)
                .slideY(begin: 0.3, end: 0, curve: Curves.easeOut),
            const SizedBox(height: 40),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(
                  Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ).animate(delay: 500.ms).fadeIn(duration: 300.ms),
          ],
        ),
      ),
    );
  }
}
