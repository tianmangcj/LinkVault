import 'package:flutter/material.dart';

import 'di/app_dependencies.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class LinkVaultApp extends StatefulWidget {
  const LinkVaultApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<LinkVaultApp> createState() => _LinkVaultAppState();
}

class _LinkVaultAppState extends State<LinkVaultApp>
    with WidgetsBindingObserver {
  bool _discardingTransfers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _discardTransfers();
    }
  }

  Future<void> _discardTransfers() async {
    if (_discardingTransfers) {
      return;
    }
    _discardingTransfers = true;
    try {
      await widget.dependencies.transferResumeService
          .discardInterruptedTransfers();
    } finally {
      _discardingTransfers = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DependenciesScope(
      dependencies: widget.dependencies,
      child: MaterialApp(
        title: 'LinkVault',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        initialRoute: AppRoute.authGate.path,
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }
}
