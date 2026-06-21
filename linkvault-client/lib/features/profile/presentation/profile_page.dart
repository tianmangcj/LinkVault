import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/di/app_dependencies.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/linkvault_models.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/vault_widgets.dart';
import '../../files/presentation/file_list_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<_ProfileData> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _load();
      _initialized = true;
    }
  }

  Future<_ProfileData> _load() async {
    final api = DependenciesScope.of(context).apiClient;
    final results = await Future.wait<Object?>([
      _optional(api.me()),
      _optional(api.quota()),
    ]);
    final connectionFailure = results.any(
      (result) => result is _NetworkConnectionFailure,
    );
    return _ProfileData(
      user: connectionFailure
          ? null
          : (results[0] is UserProfile ? results[0] as UserProfile : null),
      quota: connectionFailure
          ? null
          : (results[1] is QuotaInfo ? results[1] as QuotaInfo : null),
      connectionFailure: connectionFailure,
    );
  }

  Future<Object?> _optional<T>(Future<T> future) async {
    try {
      return await future;
    } catch (error) {
      if (isNetworkConnectionFailure(error)) {
        return const _NetworkConnectionFailure();
      }
      return null;
    }
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _logout() async {
    final confirmed = await showAppConfirmation(
      context,
      title: '退出登录',
      message: '要退出当前账号吗？下次使用需要重新登录。',
      confirmLabel: '退出',
      icon: Icons.logout,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final dependencies = DependenciesScope.of(context);
    unawaited(dependencies.apiClient.logout().catchError((_) {}));
    try {
      await dependencies.tokenStorage.clear();
    } catch (_) {}
    if (!mounted) {
      return;
    }
    AppShell.resetNavigationHistory();
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoute.login.path, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: '我的',
      currentRoute: AppRoute.profile,
      body: SimplePage(
        header: PageIntro(
          title: '个人中心',
          leadingIcon: Icons.person_outline,
          trailing: IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ),
        children: [
          FutureBuilder<_ProfileData>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.hasError
                  ? const _ProfileData()
                  : snapshot.data ?? const _ProfileData();
              if (data.connectionFailure) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  showNetworkConnectionFailureSnackBar(context);
                });
              }
              return Column(
                children: spaceChildren([
                  if (data.user != null) _UserPanel(user: data.user!),
                  if (data.quota != null) _StoragePanel(quota: data.quota!),
                  _SettingsPanel(
                    onAccount: () => AppShell.goTo(context, AppRoute.account),
                    onDevices: () => AppShell.goTo(context, AppRoute.devices),
                    onLogout: _logout,
                  ),
                ], 16),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileData {
  const _ProfileData({
    this.user,
    this.quota,
    this.connectionFailure = false,
  });

  final UserProfile? user;
  final QuotaInfo? quota;
  final bool connectionFailure;
}

class _NetworkConnectionFailure {
  const _NetworkConnectionFailure();
}

class _UserPanel extends StatelessWidget {
  const _UserPanel({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarBytes = _decodeAvatarData(user.avatarImageData);

    return SimplePanel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage: avatarBytes == null
                ? null
                : MemoryImage(avatarBytes),
            child: avatarBytes == null
                ? Text(
                    user.avatarText,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              user.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Uint8List? _decodeAvatarData(String? avatarImageData) {
    if (avatarImageData == null) {
      return null;
    }
    final comma = avatarImageData.indexOf(',');
    if (comma < 0) {
      return null;
    }
    try {
      return base64Decode(avatarImageData.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }
}

class _StoragePanel extends StatelessWidget {
  const _StoragePanel({required this.quota});

  final QuotaInfo quota;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final percent = (quota.usageRatio.clamp(0, 1) * 100).round();

    return SimplePanel(
      title: '存储空间',
      trailing: StatusText('$percent%', icon: Icons.pie_chart_outline),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: quota.usageRatio.clamp(0, 1).toDouble(),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '已用 ${formatBytes(quota.usedBytes)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              Text(
                '剩余 ${formatBytes(quota.availableBytes)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.onAccount,
    required this.onDevices,
    required this.onLogout,
  });

  final VoidCallback onAccount;
  final VoidCallback onDevices;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final settingTitleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

    return SimplePanel(
      title: '设置',
      child: Column(
        children: [
          SimpleListRow(
            icon: Icons.manage_accounts_outlined,
            title: '账号管理',
            titleStyle: settingTitleStyle,
            trailing: const Icon(Icons.chevron_right),
            onTap: onAccount,
          ),
          const SectionDivider(),
          SimpleListRow(
            icon: Icons.devices_outlined,
            title: '设备管理',
            titleStyle: settingTitleStyle,
            trailing: const Icon(Icons.chevron_right),
            onTap: onDevices,
          ),
          const SectionDivider(),
          SimpleListRow(
            icon: Icons.logout,
            title: '退出登录',
            titleStyle: settingTitleStyle,
            trailing: const Icon(Icons.chevron_right),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}
