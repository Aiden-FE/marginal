import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'poster.dart';

/// 用 PictureRecorder 同步光栅化海报并编码 PNG。
/// 与 widget 树无关，可在任意时机调用（打开 sheet 时预渲染，避免
/// iOS Safari 要求 navigator.share 必须处于用户手势栈内）。
Future<Uint8List> renderPosterPng({
  required String workTitle,
  required String chapterTitle,
  required String text,
  double pixelRatio = 2,
}) async {
  final lines = wrapPosterText(text);
  final height = (520 + lines.length * 62).clamp(1200, 2400).toDouble();
  const width = 900.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawPaint(Paint()..color = const Color(0xFFF7F0DF));
  ParagraphPosterPainter(
    workTitle: workTitle,
    chapterTitle: chapterTitle,
    text: text,
  ).paint(canvas, Size(width, height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (width * pixelRatio).round(),
    (height * pixelRatio).round(),
  );
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw StateError('海报编码失败');
  return data.buffer.asUint8List();
}
