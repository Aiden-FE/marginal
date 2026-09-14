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
    expect(find.text('书库'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('AI 工作区'), findsOneWidget);
    expect(find.text('AI 供应商'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('阅读偏好'), findsOneWidget);
    expect(find.text('AI 供应商'), findsOneWidget);
  });
}
