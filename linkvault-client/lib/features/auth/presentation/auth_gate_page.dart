import 'package:flutter/material.dart';

import '../../../app/di/app_dependencies.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../shared/widgets/app_shell.dart';

class AuthGatePage extends StatefulWidget {
  const AuthGatePage({super.key});

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final dependencies = DependenciesScope.of(context);
    final tokens = await dependencies.tokenStorage.read();
    if (!mounted) {
      return;
    }
    if (tokens == null) {
      _goTo(AppRoute.login);
      return;
    }

    try {
      final api = dependencies.apiClient;
      await api.me();
      await api.reportCurrentDevice();
      await dependencies.transferResumeService.discardInterruptedTransfers();
      if (mounted) {
        _goTo(AppRoute.files);
      }
    } catch (error) {
      final apiError = normalizeApiError(error);
      if (apiError is UnauthorizedApiException) {
        await dependencies.tokenStorage.clear();
        if (mounted) {
          _goTo(AppRoute.login);
        }
        return;
      }
      if (mounted) {
        _goTo(AppRoute.files);
      }
    }
  }

  void _goTo(AppRoute route) {
    AppShell.resetNavigationHistory();
    Navigator.of(context).pushReplacementNamed(route.path);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(child: Center(child: Text('正在进入应用'))),
    );
  }
}
