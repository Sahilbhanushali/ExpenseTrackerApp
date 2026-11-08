import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// Shown the instant the Flutter engine attaches, replacing the native
/// static splash — native splash screens can't animate, so the brand moment
/// lives here. Always on the ink surface, independent of light/dark mode.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final text = Theme.of(context).textTheme;

    Widget logo = Container(
      width: 112,
      height: 112,
      padding: const EdgeInsets.all(AppSpacing.lg - 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl + 4),
      ),
      child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.contain),
    );
    Widget title = Text(
      'Spendo',
      style: text.headlineMedium?.copyWith(color: Colors.white),
    );
    Widget tagline = Text(
      'Money, made clear.',
      style: text.bodyMedium?.copyWith(
        color: Colors.white.withValues(alpha: 0.7),
      ),
    );
    if (!reduceMotion) {
      logo = logo
          .animate()
          .scale(
            begin: const Offset(0.6, 0.6),
            end: const Offset(1, 1),
            duration: 500.ms,
            curve: Curves.easeOutBack,
          )
          .fadeIn(duration: 300.ms);
      title = title
          .animate(delay: 180.ms)
          .fadeIn(duration: 350.ms)
          .slideY(begin: 0.3, end: 0, curve: Curves.easeOut);
      tagline = tagline.animate(delay: 320.ms).fadeIn(duration: 350.ms);
    }

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(height: AppSpacing.lg),
            title,
            const SizedBox(height: AppSpacing.xs),
            tagline,
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(
                  Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
