import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/app/platform_services.dart';
import 'package:marginal/app/reading_shell.dart';

void main() {
  testWidgets('生产壳提供书库、AI、我的三个一级 Tab', (tester) async {
    final services = await PlatformServices.boot(persistent: false);
    await tester.pumpWidget(
      MaterialApp(home: ReadingShell(services: services)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    final navContext = tester.element(find.byType(NavigationBar));
    final navTheme = NavigationBarTheme.of(navContext);
    expect(
      navTheme.iconTheme,
      isNotNull,
      reason: 'Safari 下底部 Tab 图标颜色必须显式继承，不能依赖默认主题',
    );
    expect(navTheme.labelTextStyle, isNotNull);
    expect(
      navTheme.iconTheme!.resolve({WidgetState.selected})?.color,
      isNotNull,
    );
    expect(find.text('书库'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    const navIcons = [
      Icons.menu_book_rounded,
      Icons.auto_awesome,
      Icons.person_rounded,
    ];
    const navOutlineIcons = [
      Icons.menu_book_outlined,
      Icons.auto_awesome_outlined,
      Icons.person_outline_rounded,
    ];
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            [
              ...navIcons,
              ...navOutlineIcons,
            ].any((data) => identical(widget.icon, data)),
      ),
      findsNWidgets(3),
      reason: '每个底部 Tab 必须渲染真实 Icon，而不是只剩文字色块',
    );

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('AI 工作区'), findsOneWidget);
    expect(find.text('AI 供应商'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('阅读偏好'), findsOneWidget);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('AI 供应商'), findsOneWidget);
  });
}
