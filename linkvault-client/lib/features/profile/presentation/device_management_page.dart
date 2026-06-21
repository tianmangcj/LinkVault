import 'package:flutter/material.dart';

import '../../../app/di/app_dependencies.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/linkvault_models.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/vault_widgets.dart';
import '../../files/presentation/file_list_page.dart';

class DeviceManagementPage extends StatefulWidget {
  const DeviceManagementPage({super.key});

  @override
  State<DeviceManagementPage> createState() => _DeviceManagementPageState();
}

class _DeviceManagementPageState extends State<DeviceManagementPage> {
  late Future<List<DeviceInfo>> _future;
  bool _initialized = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _load();
      _initialized = true;
    }
  }

  Future<List<DeviceInfo>> _load() async {
    final api = DependenciesScope.of(context).apiClient;
    await api.reportCurrentDevice();
    return api.devices();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _revoke(DeviceInfo device) async {
    if (_busy) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _RevokeDeviceDialog(device: device),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });
    try {
      final dependencies = DependenciesScope.of(context);
      await dependencies.apiClient.revokeDevice(device.id);
      if (!mounted) {
        return;
      }
      if (device.current) {
        await dependencies.tokenStorage.clear();
        if (!mounted) {
          return;
        }
        AppShell.resetNavigationHistory();
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoute.login.path, (route) => false);
        return;
      }
      _reload();
    } catch (error) {
      if (mounted) {
        showAppNotice(
          context,
          normalizeApiError(error).message,
          type: AppNoticeType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: '设备管理',
      currentRoute: AppRoute.devices,
      body: SimplePage(
        header: PageIntro(
          title: '设备管理',
          leadingIcon: Icons.devices_outlined,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '返回设置',
                onPressed: _busy
                    ? null
                    : () => AppShell.goBack(
                        context,
                        fallback: AppRoute.profile,
                      ),
                icon: const Icon(Icons.arrow_back),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _busy ? null : _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        children: [
          FutureBuilder<List<DeviceInfo>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _LoadingPanel();
              }
              final connectionFailure =
                  snapshot.hasError &&
                  isNetworkConnectionFailure(snapshot.error!);
              if (connectionFailure) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  showNetworkConnectionFailureSnackBar(context);
                });
              }
              return _DevicesPanel(
                devices: snapshot.hasError
                    ? const []
                    : snapshot.data ?? const [],
                showEmptyState: !snapshot.hasError,
                busy: _busy,
                onRevoke: _revoke,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DevicesPanel extends StatelessWidget {
  const _DevicesPanel({
    required this.devices,
    required this.showEmptyState,
    required this.busy,
    required this.onRevoke,
  });

  final List<DeviceInfo> devices;
  final bool showEmptyState;
  final bool busy;
  final ValueChanged<DeviceInfo> onRevoke;

  @override
  Widget build(BuildContext context) {
    return SimplePanel(
      title: '已登录设备',
      child: devices.isEmpty && showEmptyState
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text('暂无设备')),
            )
          : Column(
              children: [
                for (var index = 0; index < devices.length; index++) ...[
                  _DeviceRow(
                    device: devices[index],
                    busy: busy,
                    onRevoke: onRevoke,
                  ),
                  if (index != devices.length - 1) const SectionDivider(),
                ],
              ],
            ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.busy,
    required this.onRevoke,
  });

  final DeviceInfo device;
  final bool busy;
  final ValueChanged<DeviceInfo> onRevoke;

  @override
  Widget build(BuildContext context) {
    return SimpleListRow(
      icon: _deviceIcon(device.platform),
      title: device.deviceName,
      subtitle: '最近活跃 ${formatDateTime(device.lastSeenAt)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (device.current)
            const StatusText('当前设备', icon: Icons.check_circle_outline),
          if (device.current) const SizedBox(width: 8),
          IconButton(
            tooltip: '删除设备',
            onPressed: busy ? null : () => onRevoke(device),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  IconData _deviceIcon(String platform) {
    return switch (platform.toLowerCase()) {
      'android' => Icons.phone_android,
      'ios' => Icons.phone_iphone,
      'windows' || 'linux' => Icons.desktop_windows_outlined,
      'macos' => Icons.laptop_mac,
      'web' => Icons.language,
      _ => Icons.devices_outlined,
    };
  }
}

class _RevokeDeviceDialog extends StatelessWidget {
  const _RevokeDeviceDialog({required this.device});

  final DeviceInfo device;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('删除设备'),
      content: Text(
        device.current
            ? '删除当前设备后，本机将退出登录。'
            : '要删除“${device.deviceName}”吗？该设备下次打开应用时需要重新登录。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('删除'),
        ),
      ],
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const SimplePanel(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text('正在加载设备'),
        ),
      ),
    );
  }
}
