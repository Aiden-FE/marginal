import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 段落海报 —— 视觉移植自 v1 `poster.ts`（900 宽暖纸渐变 + 双环装饰 + 衬线正文）。
List<String> wrapPosterText(
  String text, {
  int maxUnits = 20,
  int maxLines = 18,
}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];
  final lines = <String>[];
  var line = '';
  var units = 0.0;
  var truncated = false;
  for (final character in normalized.runes) {
    final ch = String.fromCharCode(character);
    final width = RegExp(r'[\x00-\xff]').hasMatch(ch) ? 0.55 : 1.0;
    if (line.isNotEmpty && units + width > maxUnits) {
      lines.add(line.trimRight());
      line = '';
      units = 0;
      if (lines.length == maxLines) {
        truncated = true;
        break;
      }
    }
    line += ch;
    units += width;
  }
  if (line.isNotEmpty && lines.length < maxLines) lines.add(line.trimRight());
  if (truncated && lines.isNotEmpty) {
    lines[lines.length - 1] =
        '${lines.last.replaceFirst(RegExp(r'[，。！？；：,.!?;:]?$'), '')}…';
  }
  return lines;
}

class ParagraphPosterPainter extends CustomPainter {
  ParagraphPosterPainter({
    required this.workTitle,
    required this.chapterTitle,
    required this.text,
  });

  final String workTitle, chapterTitle, text;

  @override
  void paint(Canvas canvas, Size size) {
    final lines = wrapPosterText(text);
    const width = 900.0;
    final height = (520 + lines.length * 62).clamp(1200, 2400).toDouble();
    final rect = Offset.zero & size;
    canvas.scale(rect.width / width, rect.height / height);

    final background = Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, height), [
        const Color(0xFFF7F0DF),
        const Color(0xFFE9DCC2),
      ]);
    canvas.drawRect(Offset.zero & Size(width, height), background);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0x479E6C30);
    canvas.drawCircle(const Offset(790, 105), 155, ring);
    canvas.drawCircle(const Offset(790, 105), 110, ring);

    void text_(String value, Offset at, TextStyle style, {double spacing = 0}) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, at);
    }

    const brand = TextStyle(
      color: Color(0xFF9D6B2F),
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: 3,
    );
    text_('MARGINAL READING', const Offset(78, 92), brand);

    const label = TextStyle(
      color: Color(0xFF8A6A3C),
      fontSize: 20,
      letterSpacing: 2,
    );
    text_(workTitle, const Offset(78, 190), label);
    const chapterStyle = TextStyle(
      color: Color(0xFF3A332A),
      fontSize: 34,
      fontWeight: FontWeight.w700,
    );
    text_(chapterTitle, const Offset(78, 230), chapterStyle);

    const body = TextStyle(
      color: Color(0xFF2F2A22),
      fontSize: 30,
      height: 1.9,
      fontFamily: 'Songti SC',
    );
    var y = 330.0;
    for (final line in lines) {
      text_(line, Offset(78, y), body);
      y += 62;
    }

    const footer = TextStyle(
      color: Color(0xFF8A6A3C),
      fontSize: 18,
      letterSpacing: 1.5,
    );
    text_('— Marginal 阅读摘录 —', Offset(78, height - 90), footer);
  }

  @override
  bool shouldRepaint(covariant ParagraphPosterPainter old) =>
      old.workTitle != workTitle ||
      old.chapterTitle != chapterTitle ||
      old.text != text;
}
