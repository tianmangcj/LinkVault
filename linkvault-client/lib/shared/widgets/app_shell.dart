import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/router/app_router.dart';
import 'app_feedback.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    required this.title,
    required this.body,
    this.currentRoute,
    this.actions = const [],
    super.key,
  });

  final String title;
  final AppRoute? currentRoute;
  final Widget body;
  final List<Widget> actions;

  static final List<AppRoute> _routeHistory = <AppRoute>[];
  static DateTime? _lastRootBackPressedAt;

  static void resetNavigationHistory() {
    _routeHistory.clear();
    _lastRootBackPressedAt = null;
  }

  @override
  Widget build(BuildContext context) {
    if (currentRoute == null) {
      return Scaffold(body: SafeArea(child: body));
    }

    final shell = LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 600;

        if (useRail) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _WorkspaceRail(currentRoute: currentRoute!),
                  VerticalDivider(
                    width: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  Expanded(
                    child: AppFeedbackAnchor(
                      windowsSnackBarBottomMargin: 48,
                      child: Column(
                        children: [
                          if (actions.isNotEmpty)
                            _DesktopCommandBar(actions: actions),
                          Expanded(child: body),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          appBar: actions.isEmpty
              ? null
              : AppBar(automaticallyImplyLeading: false, actions: actions),
          body: SafeArea(child: body),
          bottomNavigationBar: NavigationBar(
            selectedIndex: AppRoute.workspaceRoutes.indexOf(
              _workspaceSelectionFor(currentRoute!),
            ),
            onDestinationSelected: (index) {
              goTo(context, AppRoute.workspaceRoutes[index]);
            },
            destinations: [
              for (final route in AppRoute.workspaceRoutes)
                NavigationDestination(
                  icon: Icon(route.icon),
                  selectedIcon: Icon(_selectedIconFor(route)),
                  label: route.label,
                ),
            ],
          ),
        );
      },
    );

    final isAndroid = Theme.of(context).platform == TargetPlatform.android;
    if (!isAndroid) {
      return shell;
    }

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _handleAndroidBack(context);
      },
      child: shell,
    );
  }

  static void goTo(BuildContext context, AppRoute route) {
    final currentRoute = _routeFromContext(context);
    if (route == currentRoute) {
      return;
    }
    if (currentRoute != null) {
      _routeHistory.add(currentRoute);
    }
    _replaceWithoutRecording(context, route);
  }

  static bool goBack(BuildContext context, {AppRoute? fallback}) {
    final currentRoute = _routeFromContext(context);
    while (_routeHistory.isNotEmpty) {
      final previousRoute = _routeHistory.removeLast();
      if (previousRoute != currentRoute) {
        _replaceWithoutRecording(context, previousRoute);
        return true;
      }
    }

    if (fallback != null && fallback != currentRoute) {
      _replaceWithoutRecording(context, fallback);
      return true;
    }

    return false;
  }

  static void _replaceWithoutRecording(BuildContext context, AppRoute route) {
    _lastRootBackPressedAt = null;
    Navigator.of(context).pushReplacementNamed(route.path);
  }

  static AppRoute? _routeFromContext(BuildContext context) {
    final currentName = ModalRoute.of(context)?.settings.name;
    for (final route in AppRoute.values) {
      if (route.path == currentName) {
        return route;
      }
    }
    return null;
  }

  static void _handleAndroidBack(BuildContext context) {
    final currentRoute = _routeFromContext(context);
    final isWorkspaceRoot =
        currentRoute != null && AppRoute.workspaceRoutes.contains(currentRoute);
    if (!isWorkspaceRoot && goBack(context)) {
      return;
    }

    final now = DateTime.now();
    final shouldExit =
        _lastRootBackPressedAt != null &&
        now.difference(_lastRootBackPressedAt!) <= const Duration(seconds: 2);
    if (shouldExit) {
      SystemNavigator.pop();
      return;
    }

    _lastRootBackPressedAt = now;
    showCompactAppSnackBar(context, '再按一次退出应用');
  }
}

class _DesktopCommandBar extends StatelessWidget {
  const _DesktopCommandBar({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        child: Row(children: [const Spacer(), ...actions]),
      ),
    );
  }
}

class _WorkspaceRail extends StatelessWidget {
  const _WorkspaceRail({required this.currentRoute});

  final AppRoute currentRoute;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 92,
      child: NavigationRail(
        selectedIndex: AppRoute.workspaceRoutes.indexOf(
          _workspaceSelectionFor(currentRoute),
        ),
        labelType: NavigationRailLabelType.all,
        leading: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 14),
          child: Tooltip(
            message: 'LinkVault',
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                color: colorScheme.primary,
              ),
            ),
          ),
        ),
        onDestinationSelected: (index) {
          AppShell.goTo(context, AppRoute.workspaceRoutes[index]);
        },
        destinations: [
          for (final route in AppRoute.workspaceRoutes)
            NavigationRailDestination(
              icon: Icon(route.icon),
              selectedIcon: Icon(_selectedIconFor(route)),
              label: Text(route.label),
            ),
        ],
      ),
    );
  }
}

IconData _selectedIconFor(AppRoute route) {
  return switch (route) {
    AppRoute.files => Icons.folder,
    AppRoute.tasks => Icons.swap_vert_circle,
    AppRoute.recycleBin => Icons.delete,
    AppRoute.profile => Icons.person,
    AppRoute.account => Icons.manage_accounts,
    AppRoute.devices => Icons.devices,
    AppRoute.authGate => route.icon,
    AppRoute.login => route.icon,
    AppRoute.register => route.icon,
  };
}

AppRoute _workspaceSelectionFor(AppRoute route) {
  return switch (route) {
    AppRoute.account || AppRoute.devices => AppRoute.profile,
    _ => route,
  };
}
