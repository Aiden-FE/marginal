import 'package:flutter/material.dart';

/// 阅读区调色板（纸/护眼/夜间），由 MarginalColors 提供。
class ReaderPalette {
  const ReaderPalette({
    required this.background,
    required this.foreground,
    required this.chrome,
    required this.accent,
  });
  final Color background, foreground, chrome, accent;
}

/// 阅读主题：纸 / 护眼 / 夜间（与 v1 一致）。
enum ReaderTheme { paper, eyecare, dark }
