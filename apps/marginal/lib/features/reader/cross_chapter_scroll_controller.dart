import 'package:flutter/widgets.dart';

/// 自定义 ScrollController，把 [goBallistic] 的边界 fling 转成回调。
///
/// Flutter 框架对 [ScrollPosition.activity] 做了 visible-for-testing 限制，
/// 无法在 widget 代码里直接读 fling 速度。覆写 [ScrollPositionWithSingleContext.goBallistic]
/// 是拿到「拖拽松手时 fling 是否在边界、速度多大」这一信号的标准入口。
class CrossChapterScrollController extends ScrollController {
  CrossChapterScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.onEdgeFling,
  });

  /// 在边界触发的 fling 回调：
  ///   [velocity] —— 沿 axisDirection 的 pixels/秒，positive = forward（向下）
  ///   [pixels] / [minExtent] / [maxExtent] —— fling 起点的滚动位置与边界。
  /// 仅在 [pixels] 处于任一边界时调用；不在边界时不会被调。
  void Function(double velocity, double pixels, double minExtent, double maxExtent)?
      onEdgeFling;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _CrossChapterScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      onEdgeFling: onEdgeFling,
    );
  }
}

class _CrossChapterScrollPosition extends ScrollPositionWithSingleContext {
  _CrossChapterScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required super.initialPixels,
    super.keepScrollOffset,
    this.onEdgeFling,
  });

  void Function(double velocity, double pixels, double minExtent, double maxExtent)?
      onEdgeFling;

  @override
  void goBallistic(double velocity) {
    final min = minScrollExtent;
    final max = maxScrollExtent;
    final atMin = pixels <= min + 0.5;
    final atMax = pixels >= max - 0.5;
    if ((atMin || atMax) && velocity.abs() > 0 && onEdgeFling != null) {
      onEdgeFling!(velocity, pixels, min, max);
    }
    super.goBallistic(velocity);
  }
}

