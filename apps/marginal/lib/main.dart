import 'package:flutter/material.dart';

import 'app/marginal_app.dart';
import 'app/platform_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await PlatformServices.boot();
  runApp(MarginalApp(services: services));
}
