import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Original vector artwork. The animation never chooses or changes an item.
class GachaMachine extends StatelessWidget {
  const GachaMachine({super.key, this.progress = 0, this.instant = false});
  final double progress;
  final bool instant;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        width: 280,
        height: 330,
        child: CustomPaint(
          painter: GachaPainter(
            progress,
            Theme.of(context).brightness == Brightness.dark,
            instant,
          ),
        ),
      ),
    ),
  );
}

class GachaPainter extends CustomPainter {
  GachaPainter(this.progress, this.dark, this.instant);
  final double progress;
  final bool dark;
  final bool instant;
  static const green = Color(0xFF557B64);
  static const ink = Color(0xFF355B49);
  static const colors = [
    Color(0xFFC6B5DA),
    Color(0xFFA5BEA5),
    Color(0xFFE3BCA4),
    Color(0xFFADC4CF),
  ];

  void rounded(Canvas c, Rect r, double radius, Color color) => c.drawRRect(
    RRect.fromRectAndRadius(r, Radius.circular(radius)),
    Paint()..color = color,
  );

  void capsule(
    Canvas c,
    Offset center,
    double r,
    Color color, {
    double rotation = 0,
    double separation = 0,
  }) {
    c.save();
    c.translate(center.dx, center.dy);
    c.rotate(rotation);
    c.save();
    c.translate(-separation, 0);
    c.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r),
      math.pi / 2,
      math.pi,
      true,
      Paint()..color = color,
    );
    c.restore();
    c.save();
    c.translate(separation, 0);
    c.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: r),
      -math.pi / 2,
      math.pi,
      true,
      Paint()..color = dark ? const Color(0xFFDFDFCE) : const Color(0xFFFFFCF7),
    );
    c.restore();
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 280, size.height / 330);
    if (instant) {
      canvas.drawOval(
        const Rect.fromLTWH(79, 247, 122, 12),
        Paint()..color = ink.withValues(alpha: .08),
      );
      capsule(canvas, const Offset(140, 174), 62, colors[0], rotation: -.35);
      canvas.restore();
      return;
    }
    canvas.drawOval(
      const Rect.fromLTWH(62, 294, 156, 14),
      Paint()..color = ink.withValues(alpha: .10),
    );
    rounded(canvas, const Rect.fromLTWH(58, 174, 164, 112), 24, green);
    rounded(canvas, const Rect.fromLTWH(72, 278, 22, 14), 5, ink);
    rounded(canvas, const Rect.fromLTWH(186, 278, 22, 14), 5, ink);
    final globe = Rect.fromCircle(center: const Offset(140, 106), radius: 88);
    canvas.drawOval(
      globe,
      Paint()..color = dark ? const Color(0xFF303A32) : const Color(0xFFF0F1E8),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(globe.deflate(3)));
    const centers = [
      Offset(89, 113),
      Offset(126, 131),
      Offset(167, 142),
      Offset(194, 111),
      Offset(111, 168),
      Offset(151, 172),
      Offset(146, 94),
    ];
    final stir = progress > .08 && progress < .41;
    for (var i = 0; i < centers.length; i++) {
      final phase = (progress - .08) * 30 + i;
      final delta = stir
          ? Offset(math.sin(phase) * 8, math.cos(phase * 1.3) * 7)
          : Offset.zero;
      capsule(
        canvas,
        centers[i] + delta,
        17,
        colors[i % colors.length],
        rotation: (i - 3) * .37 + (stir ? math.sin(phase) * .18 : 0),
      );
    }
    canvas.restore();
    canvas.drawOval(
      globe,
      Paint()
        ..color = dark ? const Color(0xFF6E8372) : const Color(0xFFCCD7CA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawArc(
      globe.deflate(12),
      3.55,
      .8,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: dark ? .10 : .8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
    rounded(canvas, const Rect.fromLTWH(114, 12, 52, 14), 7, ink);
    rounded(canvas, const Rect.fromLTWH(80, 176, 120, 15), 7, ink);
    canvas.drawCircle(
      const Offset(140, 220),
      25,
      Paint()..color = dark ? const Color(0xFFDFDFCE) : const Color(0xFFFFFCF7),
    );
    canvas.save();
    canvas.translate(140, 220);
    final turn = progress > 0
        ? math.sin((progress / .08).clamp(0, 1) * math.pi / 2) * .85
        : 0.0;
    canvas.rotate(turn);
    rounded(canvas, const Rect.fromLTWH(-17, -5, 34, 10), 5, ink);
    canvas.restore();
    rounded(canvas, const Rect.fromLTWH(108, 253, 64, 25), 9, ink);
    if (progress >= .405) {
      final t = ((progress - .405) / .215).clamp(0.0, 1.0);
      final drop = Curves.easeOut.transform(t) * 34;
      final separation = ((progress - .62) / .30).clamp(0.0, 1.0) * 18;
      capsule(
        canvas,
        Offset(140, 271 + drop),
        20,
        colors[0],
        rotation: -.15,
        separation: separation,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(GachaPainter old) =>
      old.progress != progress || old.dark != dark || old.instant != instant;
}
