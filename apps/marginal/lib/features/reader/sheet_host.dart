import 'dart:async';

import 'package:flutter/widgets.dart';

/// 阅读器所有弹层共享的 "先收起再执行" 动作值类型。
///
/// 把 5 个 sheet 中分散的 `Navigator.pop` + 260ms `Future.delayed` 模式
/// 收敛到一处，避免每个 sheet 重新发明同一段时序。
class SheetAction {
  const SheetAction(this.label, this.run);

  final String label;
  final FutureOr<void> Function() run;
}

/// 先关闭弹层，再延迟 260ms 执行回调。
///
/// 260ms 是 Flutter `Navigator.pop` 退场动画时长，留出退场动画再触发
/// 后续动作，避免用户感知到弹层还没收起就跳转/弹新页面。
Future<void> popAndRun(BuildContext context, FutureOr<void> Function()? action) async {
  if (action == null) {
    Navigator.of(context).pop();
    return;
  }
  Navigator.of(context).pop();
  await Future<void>.delayed(const Duration(milliseconds: 260));
  await action();
}