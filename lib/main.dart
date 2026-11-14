import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/platform.dart';
import 'app/services.dart';
import 'desktop/desktop_integration.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isNativeDesktop) await DesktopIntegration.initWindow();
  runApp(NeteaseClientApp(services: await AppServices.create()));
}
