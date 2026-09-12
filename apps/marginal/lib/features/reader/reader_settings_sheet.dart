import 'package:flutter/material.dart';

import '../../app/marginal_theme.dart';
import 'reader_theme.dart' show ReaderTheme;

/// 阅读设置 bottom sheet —— 字号 / 主题 / 行距 / 自动阅读（与 v1 设置面板对齐）。
///
/// 面板持有本地状态使 slider 实时反映；每次变更通过回调上抛，
/// 由 ReaderPage 落库到 Work.settings（`reader.fontSize` 等）。
class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.fontSize,
    required this.lineHeight,
    required this.theme,
    required this.autoSpeed,
    required this.autoRunning,
    required this.onFontSize,
    required this.onLineHeight,
    required this.onTheme,
    required this.onAutoSpeed,
    required this.onAutoToggle,
  });

  final double fontSize;
  final double lineHeight;
  final ReaderTheme theme;
  final int autoSpeed;
  final bool autoRunning;
  final ValueChanged<double> onFontSize;
  final ValueChanged<double> onLineHeight;
  final ValueChanged<ReaderTheme> onTheme;
  final ValueChanged<int> onAutoSpeed;
  final ValueChanged<bool> onAutoToggle;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  static const _labels = {
    ReaderTheme.paper: '纸张',
    ReaderTheme.eyecare: '护眼',
    ReaderTheme.dark: '夜间',
  };

  late double _fontSize = widget.fontSize;
  late double _lineHeight = widget.lineHeight;
  late ReaderTheme _theme = widget.theme;
  late int _autoSpeed = widget.autoSpeed;
  late bool _autoRunning = widget.autoRunning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '阅读设置',
              style: MarginalTheme.serif.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            _sectionLabel('字号'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const Key('font-size-slider'),
                    value: _fontSize,
                    min: 14,
                    max: 30,
                    divisions: 16,
                    label: _fontSize.toStringAsFixed(0),
                    onChanged: (v) {
                      setState(() => _fontSize = v);
                      widget.onFontSize(v);
                    },
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    _fontSize.toStringAsFixed(0),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            _sectionLabel('主题'),
            Row(
              children: [
                for (final theme in ReaderTheme.values)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: theme == ReaderTheme.dark ? 0 : 8,
                      ),
                      child: _themeCard(theme),
                    ),
                  ),
              ],
            ),
            _sectionLabel('行距'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const Key('line-height-slider'),
                    value: _lineHeight,
                    min: 1.6,
                    max: 2.2,
                    divisions: 6,
                    label: _lineHeight.toStringAsFixed(1),
                    onChanged: (v) {
                      setState(() => _lineHeight = v);
                      widget.onLineHeight(v);
                    },
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    _lineHeight.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text('自动阅读', style: TextStyle(fontSize: 14)),
                ),
                Switch(
                  key: const Key('auto-switch'),
                  value: _autoRunning,
                  onChanged: (v) {
                    setState(() => _autoRunning = v);
                    widget.onAutoToggle(v);
                  },
                ),
              ],
            ),
            _sectionLabel('自动阅读速度（$_autoSpeed px/秒）'),
            Slider(
              key: const Key('auto-speed-slider'),
              value: _autoSpeed.toDouble(),
              min: 20,
              max: 180,
              divisions: 32,
              label: '$_autoSpeed',
              onChanged: (v) {
                setState(() => _autoSpeed = v.round());
                widget.onAutoSpeed(v.round());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
    ),
  );

  Widget _themeCard(ReaderTheme theme) {
    final palette = MarginalColors.palette(theme, Theme.of(context).brightness);
    final selected = theme == _theme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        setState(() => _theme = theme);
        widget.onTheme(theme);
      },
      child: Container(
        key: Key('theme-${theme.name}'),
        height: 60,
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? palette.accent : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '字',
              style: TextStyle(
                color: palette.foreground,
                fontSize: 16,
                height: 1.2,
              ),
            ),
            Text(
              _labels[theme]!,
              style: TextStyle(color: palette.foreground, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
