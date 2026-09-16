import 'package:flutter/material.dart';

import '../../app/vector_icons.dart';

class ChromeIconButton extends StatelessWidget {
  const ChromeIconButton({
    super.key,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.tooltip,
  });

  final VectorIconKind icon;
  final Color color;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: .12)
        : Colors.black.withValues(alpha: .06);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: IconButton(
          tooltip: tooltip,
          icon: VectorIcon(icon, color: color, size: 21),
          onPressed: onPressed,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
