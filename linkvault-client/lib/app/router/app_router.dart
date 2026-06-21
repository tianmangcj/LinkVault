import 'package:flutter/material.dart';

import '../../features/auth/presentation/auth_gate_page.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/auth/presentation/register_page.dart';
import '../../features/files/presentation/file_list_page.dart';
import '../../features/profile/presentation/account_management_page.dart';
import '../../features/profile/presentation/device_management_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../../features/recycle_bin/presentation/recycle_bin_page.dart';
import '../../features/transfers/presentation/task_center_page.dart';

enum AppRoute {
  authGate('/', '启动', Icons.inventory_2_outlined),
  login('/login', '登录', Icons.lock_outline),
  register('/register', '注册', Icons.person_add_alt),
  files('/files', '存储', Icons.folder_outlined),
  tasks('/tasks', '传输', Icons.swap_vert),
  recycleBin('/recycle-bin', '回收站', Icons.delete_outline),
  profile('/profile', '我的', Icons.person_outline),
  account('/settings/account', '账号管理', Icons.manage_accounts_outlined),
  devices('/settings/devices', '设备管理', Icons.devices_outlined);

  const AppRoute(this.path, this.label, this.icon);

  final String path;
  final String label;
  final IconData icon;

  bool get isWorkspaceRoute => workspaceRoutes.contains(this);

  bool get usesWorkspaceShell =>
      isWorkspaceRoute || this == AppRoute.account || this == AppRoute.devices;

  static const workspaceRoutes = [files, tasks, recycleBin, profile];
}

class AppRouter {
  const AppRouter._();

  static Route<void> onGenerateRoute(RouteSettings settings) {
    final route = _match(settings.name);
    final page = switch (route) {
      AppRoute.authGate => const AuthGatePage(),
      AppRoute.login => const LoginPage(),
      AppRoute.register => const RegisterPage(),
      AppRoute.files => const FileListPage(),
      AppRoute.tasks => const TaskCenterPage(),
      AppRoute.recycleBin => const RecycleBinPage(),
      AppRoute.profile => const ProfilePage(),
      AppRoute.account => const AccountManagementPage(),
      AppRoute.devices => const DeviceManagementPage(),
      null => const LoginPage(),
    };

    if (route != null &&
        (route.usesWorkspaceShell ||
            route == AppRoute.login ||
            route == AppRoute.register)) {
      return PageRouteBuilder<void>(
        settings: settings,
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );
    }

    return MaterialPageRoute<void>(settings: settings, builder: (_) => page);
  }

  static AppRoute? _match(String? path) {
    for (final route in AppRoute.values) {
      if (route.path == path) {
        return route;
      }
    }
    return null;
  }
}
