import 'package:flutter_test/flutter_test.dart';

import 'package:marginal/app/marginal_app.dart';
import 'package:marginal/app/platform_services.dart';

void main() {
  testWidgets('Marginal boots into the local library', (tester) async {
    final services = await PlatformServices.boot(persistent: false);
    await tester.pumpWidget(MarginalApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('书库'), findsOneWidget);
    expect(find.textContaining('还没有书稿'), findsOneWidget);
  });
}
