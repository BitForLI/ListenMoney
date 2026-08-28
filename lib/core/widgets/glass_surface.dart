import 'dart:ui';

import 'package:flutter/material.dart';

const hazeControlGlassTint = Color(0xCCE5E7E9);
const hazeGlassInk = Color(0xFF263444);
const hazeControlGlassBlur = 26.0;
const hazeScreenInset = 10.0;
const hazeBottomPanelHeight = 133.0;

class MainNavigationRow extends StatelessWidget {
  const MainNavigationRow({
    super.key,
    required this.onProgress,
    required this.onLibrary,
    required this.onTranscript,
    this.selectedIndex,
  });

  final VoidCallback? onProgress;
  final VoidCallback? onLibrary;
  final VoidCallback? onTranscript;
  final int? selectedIndex;

  static const _destinations = [
    (Icons.bar_chart_rounded, 'Progress', '打开进度'),
    (Icons.podcasts_rounded, 'Library', '返回 BANK'),
    (Icons.subtitles_rounded, 'Transcript', '查看文本'),
  ];

  VoidCallback? _action(int index) => switch (index) {
    0 => onProgress,
    1 => onLibrary,
    _ => onTranscript,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: Row(
        children: List.generate(_destinations.length, (index) {
          final destination = _destinations[index];
          final selected = index == selectedIndex;
          final action = _action(index);
          final icon = Center(
            child: Icon(
              destination.$1,
              size: 28,
              color: action == null
                  ? hazeGlassInk.withValues(alpha: 0.28)
                  : selected
                  ? hazeGlassInk
                  : const Color(0xFF45474C),
            ),
          );
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Semantics(
                label: destination.$2,
                selected: selected,
                button: true,
                enabled: action != null,
                child: Tooltip(
                  message: destination.$3,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: action,
                    child: selected
                        ? GlassSurface(
                            blur: hazeControlGlassBlur,
                            tint: hazeControlGlassTint,
                            borderRadius: BorderRadius.circular(30),
                            child: icon,
                          )
                        : icon,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 22,
    this.dark = false,
    this.tint,
    this.refractiveEdge = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final bool dark;
  final Color? tint;
  final bool refractiveEdge;

  @override
  Widget build(BuildContext context) {
    final effectiveTint =
        tint ??
        (dark
            ? const Color(0xFF171719).withValues(alpha: 0.50)
            : Colors.white.withValues(alpha: 0.48));
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.30 : 0.13),
              blurRadius: dark ? 28 : 30,
              spreadRadius: -6,
              offset: const Offset(0, 13),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: dark ? 0.04 : 0.34),
              blurRadius: 10,
              spreadRadius: -5,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.mirror,
            ),
            blendMode: BlendMode.srcOver,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                Positioned.fill(child: ColoredBox(color: effectiveTint)),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: dark
                              ? [
                                  Colors.white.withValues(alpha: 0.13),
                                  Colors.white.withValues(alpha: 0.035),
                                  Colors.black.withValues(alpha: 0.20),
                                ]
                              : [
                                  Colors.white.withValues(alpha: 0.54),
                                  Colors.white.withValues(alpha: 0.17),
                                  Colors.white.withValues(alpha: 0.08),
                                ],
                        ),
                      ),
                    ),
                  ),
                ),
                child,
                if (refractiveEdge)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _LiquidGlassPainter(
                          borderRadius: borderRadius,
                          dark: dark,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidGlassPainter extends CustomPainter {
  const _LiquidGlassPainter({required this.borderRadius, required this.dark});

  final BorderRadius borderRadius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final outer = borderRadius.toRRect(rect).deflate(0.55);
    canvas.save();
    canvas.clipRRect(outer);

    // The radial shader mimics the bright refraction found on the upper edge
    // of Apple's glass surfaces without washing out the content below it.
    final glowPaint = Paint()
      ..blendMode = BlendMode.softLight
      ..shader = RadialGradient(
        center: const Alignment(-0.72, -1.05),
        radius: 1.28,
        colors: [
          Colors.white.withValues(alpha: dark ? 0.24 : 0.70),
          Colors.white.withValues(alpha: dark ? 0.07 : 0.16),
          Colors.transparent,
        ],
        stops: const [0, 0.34, 1],
      ).createShader(rect);
    canvas.drawRect(rect, glowPaint);

    final lowerShade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: dark ? 0.14 : 0.045),
        ],
        stops: const [0.46, 1],
      ).createShader(rect);
    canvas.drawRect(rect, lowerShade);
    canvas.restore();

    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: dark ? 0.68 : 0.98),
          Colors.white.withValues(alpha: dark ? 0.14 : 0.30),
          Colors.white.withValues(alpha: dark ? 0.30 : 0.72),
        ],
        stops: const [0, 0.56, 1],
      ).createShader(rect);
    canvas.drawRRect(outer, edgePaint);

    final inner = borderRadius.toRRect(rect).deflate(1.7);
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.55
      ..color = Colors.white.withValues(alpha: dark ? 0.10 : 0.36);
    canvas.drawRRect(inner, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius || oldDelegate.dark != dark;
  }
}
