import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A single, slow-drifting soft-gradient background mounted once at the app
/// root (see main.dart's MaterialApp.builder) — every screen's Scaffold is
/// transparent so this shows through underneath. Mirrors the reference
/// design's animated "aurora" backdrop, but as one persistent animation
/// instead of one per screen, so it stays cheap regardless of how many
/// tabs/routes are mounted.
class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _anchors = [
    Alignment(-0.7, -0.8),
    Alignment(0.75, -0.9),
    Alignment(-0.6, 0.9),
    Alignment(0.8, 0.75),
  ];
  static const _driftedAnchors = [
    Alignment(-0.3, -0.5),
    Alignment(0.4, -0.6),
    Alignment(-0.2, 0.5),
    Alignment(0.4, 0.4),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? AppColors.voidDark : AppColors.voidLight;
    final blobs = isDark
        ? AppColors.auroraBlobsDark
        : AppColors.auroraBlobsLight;

    return ColoredBox(
      color: base,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_controller.value);
          return Stack(
            fit: StackFit.expand,
            children: List.generate(blobs.length, (i) {
              final align = Alignment.lerp(_anchors[i], _driftedAnchors[i], t)!;
              return Align(
                alignment: align,
                child: FractionallySizedBox(
                  widthFactor: 0.9,
                  heightFactor: 0.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [blobs[i], blobs[i].withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
