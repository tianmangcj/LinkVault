import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/di/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.bootstrapFromConfig();
  runApp(LinkVaultApp(dependencies: dependencies));
}
