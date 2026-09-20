import 'dart:async';

import 'package:flutter/scheduler.dart';

/// 阅读器自动阅读 tick 引擎 —— 把逐帧滚动 + 章末停留 + 弹层暂停/恢复
/// 从 `_ReaderPageState` 抽出来。
///
/// 调用方提供 4 个钩子：当前滚动驱动、是否已到真实章末、像素/秒、章末停留后回调；
/// AutoReader 只负责：
///   * 用 `Ticker` 推进时间，按调用方速度推进 1 步；
///   * 命中章末时取消 ticker，启动 `chapterDwell` 延时触发回调；
///   * 在弹层打开时停止 ticker，关闭后再恢复。
class AutoReader {
  AutoReader({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;

  Duration _lastElapsed = Duration.zero;
  Timer? _chapterEndTimer;
  bool _running = false;
  bool _pausedBySheet = false;

  void Function(double deltaSeconds)? _step;
  bool Function()? _atChapterEnd;
  void Function()? _onChapterEnd;
  void Function()? _onStateChange;
  Duration _chapterDwell = const Duration(milliseconds: 1500);

  bool get running => _running;
  bool get pausedBySheet => _pausedBySheet;

  /// 启动自动阅读。`pixelsPerSecond` 由调用方包在 `_step` 里。
  /// `atChapterEnd` 在每次 tick 前判定一次，命中则改走 chapterDwell 路径。
  void start({
    required void Function(double deltaSeconds) step,
    required bool Function() atChapterEnd,
    required void Function() onChapterEnd,
    required Duration chapterDwell,
    void Function()? onStateChange,
  }) {
    _running = true;
    _pausedBySheet = false;
    _lastElapsed = Duration.zero;
    _step = step;
    _atChapterEnd = atChapterEnd;
    _onChapterEnd = onChapterEnd;
    _chapterDwell = chapterDwell;
    _onStateChange = onStateChange;
    _ticker.start();
  }

  /// 停止自动阅读：取消 ticker 与 chapterEnd 延时，清空状态。
  void stop() {
    _ticker.stop();
    _chapterEndTimer?.cancel();
    _chapterEndTimer = null;
    _running = false;
    _pausedBySheet = false;
    _lastElapsed = Duration.zero;
    _step = null;
    _atChapterEnd = null;
    _onChapterEnd = null;
    _onStateChange?.call();
  }

  /// 弹层打开：停止 ticker 与 chapterEnd 计时，但保留 "running" 语义以便关闭后恢复。
  void pauseForSheet() {
    if (!_running) return;
    _ticker.stop();
    _chapterEndTimer?.cancel();
    _chapterEndTimer = null;
    _pausedBySheet = true;
    _onStateChange?.call();
  }

  /// 弹层关闭：在仍处于 running 状态的前提下恢复 ticker。
  void resumeAfterSheet() {
    if (_running && _pausedBySheet) {
      _pausedBySheet = false;
      _lastElapsed = Duration.zero;
      _ticker.start();
      _onStateChange?.call();
    }
  }

  /// 重新启动 ticker 但不切换 pausedBySheet —— 给切章后调用。
  /// 假定调用方已确保 `_running=true`，但 ticker 已因章节切换而废弃。
  void restart() {
    if (!_running) return;
    _ticker.stop();
    _chapterEndTimer?.cancel();
    _chapterEndTimer = null;
    _lastElapsed = Duration.zero;
    _ticker.start();
  }

  /// 暂停但不切换 pausedBySheet 标志 —— 给进度条拖动用，
  /// 拖动结束由调用方决定 `resumeAfterSheet` 或 `stop`。
  void suspendTemporarily() {
    if (!_running) return;
    _ticker.stop();
    _chapterEndTimer?.cancel();
    _chapterEndTimer = null;
  }

  void dispose() {
    _chapterEndTimer?.cancel();
    _ticker.dispose();
  }

  void _onTick(Duration elapsed) {
    if (!_running) return;
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (_atChapterEnd?.call() ?? false) {
      _ticker.stop();
      _chapterEndTimer?.cancel();
      _chapterEndTimer = Timer(_chapterDwell, _onChapterEnd!);
      return;
    }
    _step?.call(dt);
  }
}