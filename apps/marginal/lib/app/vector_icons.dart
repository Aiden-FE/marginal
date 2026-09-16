import 'package:flutter/material.dart';

class VectorIcon extends StatelessWidget {
  const VectorIcon(this.kind, {super.key, this.color, this.size = 24});

  final VectorIconKind kind;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _VectorIconPainter(
      kind,
      color ?? IconTheme.of(context).color ?? Colors.black,
    ),
  );
}

enum VectorIconKind {
  library,
  ai,
  person,
  bookmark,
  bookmarkOutline,
  sun,
  moon,
}

class _VectorIconPainter extends CustomPainter {
  _VectorIconPainter(this.kind, this.color);
  final VectorIconKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .095
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final s = size.width;
    switch (kind) {
      case VectorIconKind.library:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(s * .18, s * .16, s * .64, s * .55),
            Radius.circular(s * .08),
          ),
          p,
        );
        canvas.drawLine(Offset(s * .28, s * .83), Offset(s * .72, s * .83), p);
        canvas.drawLine(Offset(s * .35, s * .71), Offset(s * .35, s * .84), p);
      case VectorIconKind.ai:
        final path = Path()
          ..moveTo(s * .5, s * .1)
          ..lineTo(s * .59, s * .39)
          ..lineTo(s * .9, s * .5)
          ..lineTo(s * .59, s * .61)
          ..lineTo(s * .5, s * .9)
          ..lineTo(s * .41, s * .61)
          ..lineTo(s * .1, s * .5)
          ..lineTo(s * .41, s * .39)
          ..close();
        canvas.drawPath(path, p);
      case VectorIconKind.person:
        canvas.drawCircle(Offset(s * .5, s * .32), s * .16, p);
        canvas.drawArc(
          Rect.fromLTWH(s * .2, s * .52, s * .6, s * .38),
          3.35,
          2.48,
          false,
          p,
        );
      case VectorIconKind.bookmarkOutline:
        final path = Path()
          ..moveTo(s * .27, s * .14)
          ..lineTo(s * .73, s * .14)
          ..lineTo(s * .73, s * .86)
          ..lineTo(s * .5, s * .7)
          ..lineTo(s * .27, s * .86)
          ..close();
        canvas.drawPath(path, p);
      case VectorIconKind.bookmark:
        final path = Path()
          ..moveTo(s * .27, s * .14)
          ..lineTo(s * .73, s * .14)
          ..lineTo(s * .73, s * .86)
          ..lineTo(s * .5, s * .7)
          ..lineTo(s * .27, s * .86)
          ..close();
        canvas.drawPath(path, fill);
      case VectorIconKind.sun:
        canvas.drawCircle(Offset(s * .5, s * .5), s * .18, p);
        for (var i = 0; i < 8; i++) {
          final a = i * 3.1415926 / 4;
          canvas.drawLine(
            Offset(
              s * .5 + Math.cos(a) * s * .31,
              s * .5 + Math.sin(a) * s * .31,
            ),
            Offset(
              s * .5 + Math.cos(a) * s * .42,
              s * .5 + Math.sin(a) * s * .42,
            ),
            p,
          );
        }
      case VectorIconKind.moon:
        final path = Path()
          ..moveTo(s * .67, s * .12)
          ..cubicTo(s * .34, s * .17, s * .28, s * .66, s * .62, s * .85)
          ..cubicTo(s * .32, s * .94, s * .1, s * .72, s * .1, s * .5)
          ..cubicTo(s * .1, s * .25, s * .34, s * .08, s * .67, s * .12)
          ..close();
        canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _VectorIconPainter old) =>
      old.kind != kind || old.color != color;
}

class Math {
  static double cos(double x) => _cos(x);
  static double sin(double x) => _sin(x);
}

// Small lookup avoids importing dart:math just for the seven rays.
double _cos(double x) => [
  1.0,
  .707,
  0.0,
  -.707,
  -1.0,
  -.707,
  0.0,
  .707,
][(x / (3.1415926 / 4)).round() % 8];
double _sin(double x) => [
  0.0,
  .707,
  1.0,
  .707,
  0.0,
  -.707,
  -1.0,
  -.707,
][(x / (3.1415926 / 4)).round() % 8];
