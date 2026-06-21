import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app/di/app_dependencies.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/linkvault_models.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/input_constraints.dart';
import '../../../shared/widgets/vault_widgets.dart';

class AccountManagementPage extends StatefulWidget {
  const AccountManagementPage({super.key});

  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  late Future<UserProfile> _future;
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

  Future<UserProfile> _load() {
    return DependenciesScope.of(context).apiClient.me();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _rename(UserProfile user) async {
    final username = await showDialog<String>(
      context: context,
      builder: (context) => _UsernameDialog(initialUsername: user.username),
    );
    if (username == null || username.trim().isEmpty || !mounted) {
      return;
    }
    await _runAction(
      () async {
        await DependenciesScope.of(
          context,
        ).apiClient.updateUsername(username.trim());
        _reload();
      },
      errorMessage: (error) =>
          error.code == 'name_conflict' ? '用户名已存在，不能修改' : null,
    );
  }

  Future<void> _updateAvatar() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '图片',
            extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
            mimeTypes: [
              'image/png',
              'image/jpeg',
              'image/gif',
              'image/webp',
              'image/bmp',
            ],
          ),
        ],
      );
      if (file == null || !mounted) {
        return;
      }
      final mimeType = _imageMimeType(file);
      if (mimeType == null) {
        _showMessage('图片类型错误', type: AppNoticeType.error);
        return;
      }
      final bytes = await file.readAsBytes();
      final avatarData = 'data:$mimeType;base64,${base64Encode(bytes)}';
      await _runAction(
        () async {
          await DependenciesScope.of(
            context,
          ).apiClient.updateAvatar(avatarData);
          _reload();
        },
        errorMessage: (error) =>
            error.code == 'invalid_image_type' ? '图片类型错误' : null,
      );
    } on UnimplementedError {
      if (mounted) {
        _showMessage('当前平台暂不支持选择头像图片', type: AppNoticeType.warning);
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          normalizeApiError(error).message,
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _changePassword() async {
    final value = await showDialog<_PasswordFormValue>(
      context: context,
      builder: (context) => const _PasswordDialog(),
    );
    if (value == null || !mounted) {
      return;
    }
    await _runAction(
      () async {
        await DependenciesScope.of(context).apiClient.changePassword(
          oldPassword: value.oldPassword,
          newPassword: value.newPassword,
          confirmPassword: value.confirmPassword,
        );
      },
      errorMessage: (error) =>
          error.code == 'invalid_password' ? '原密码错误' : null,
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _runAction(() async {
      await DependenciesScope.of(context).apiClient.deleteAccount();
      if (!mounted) {
        return;
      }
      AppShell.resetNavigationHistory();
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoute.login.path, (route) => false);
    });
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    String? Function(ApiException error)? errorMessage,
  }) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        final apiError = normalizeApiError(error);
        _showMessage(
          errorMessage?.call(apiError) ?? apiError.message,
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

  String? _imageMimeType(XFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (mimeType != null && mimeType.startsWith('image/')) {
      return mimeType;
    }
    final extension = file.name.split('.').last.toLowerCase();
    return switch (extension) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'bmp' => 'image/bmp',
      _ => null,
    };
  }

  void _showMessage(String message, {AppNoticeType type = AppNoticeType.info}) {
    showAppNotice(context, message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: '账号管理',
      currentRoute: AppRoute.account,
      body: SimplePage(
        header: PageIntro(
          title: '账号管理',
          leadingIcon: Icons.manage_accounts_outlined,
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
          FutureBuilder<UserProfile>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const _LoadingPanel();
              }
              if (snapshot.hasError) {
                if (isNetworkConnectionFailure(snapshot.error!)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    showNetworkConnectionFailureSnackBar(context);
                  });
                }
                return const SizedBox.shrink();
              }
              final user = snapshot.data!;
              return Column(
                children: spaceChildren([
                  _AccountProfilePanel(
                    user: user,
                    busy: _busy,
                    onRename: () => _rename(user),
                    onAvatar: _updateAvatar,
                  ),
                  _SecurityPanel(
                    busy: _busy,
                    onChangePassword: _changePassword,
                    onDeleteAccount: _deleteAccount,
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

class _AccountProfilePanel extends StatelessWidget {
  const _AccountProfilePanel({
    required this.user,
    required this.busy,
    required this.onRename,
    required this.onAvatar,
  });

  final UserProfile user;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onAvatar;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

    return SimplePanel(
      title: '账号资料',
      child: Column(
        children: [
          SimpleListRow(
            icon: Icons.account_circle_outlined,
            title: user.username,
            subtitle: '用户名',
            titleStyle: titleStyle,
            trailing: const Icon(Icons.edit_outlined),
            onTap: busy ? null : onRename,
          ),
          const SectionDivider(),
          SimpleListRow(
            icon: Icons.image_outlined,
            title: '头像',
            subtitle: '点击上传图片修改头像',
            titleStyle: titleStyle,
            trailing: _AvatarPreview(user: user),
            onTap: busy ? null : onAvatar,
          ),
        ],
      ),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final data = user.avatarImageData;
    final imageBytes = data == null ? null : _decodeDataUrl(data);

    return CircleAvatar(
      radius: 22,
      backgroundColor: colorScheme.primaryContainer,
      backgroundImage: imageBytes == null ? null : MemoryImage(imageBytes),
      child: imageBytes == null
          ? Text(
              user.avatarText,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }

  static Uint8List? _decodeDataUrl(String dataUrl) {
    final comma = dataUrl.indexOf(',');
    if (comma < 0) {
      return null;
    }
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }
}

class _SecurityPanel extends StatelessWidget {
  const _SecurityPanel({
    required this.busy,
    required this.onChangePassword,
    required this.onDeleteAccount,
  });

  final bool busy;
  final VoidCallback onChangePassword;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final errorColor = Theme.of(context).colorScheme.error;

    return SimplePanel(
      title: '安全',
      child: Column(
        children: [
          SimpleListRow(
            icon: Icons.password_outlined,
            title: '修改密码',
            titleStyle: titleStyle,
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : onChangePassword,
          ),
          const SectionDivider(),
          SimpleListRow(
            icon: Icons.delete_forever_outlined,
            title: '注销账号',
            subtitle: '注销后账号和已保存文件会被删除',
            titleStyle: titleStyle?.copyWith(color: errorColor),
            trailing: Icon(Icons.chevron_right, color: errorColor),
            onTap: busy ? null : onDeleteAccount,
          ),
        ],
      ),
    );
  }
}

class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog({required this.initialUsername});

  final String initialUsername;

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUsername);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _controller.text.trim();
    final validationError = usernameError(username);
    if (validationError != null) {
      setState(() {
        _error = validationError;
      });
      return;
    }
    Navigator.of(context).pop(username);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改用户名'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 64,
              inputFormatters: usernameInputFormatters(),
              decoration: const InputDecoration(
                labelText: '用户名',
                helperText: '只能使用英文字母和数字',
                prefixIcon: Icon(Icons.account_circle_outlined),
              ),
              onChanged: (_) {
                if (_error != null) {
                  setState(() {
                    _error = null;
                  });
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: AppTheme.withPlatformFont(
                    TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final oldPassword = _oldController.text;
    final newPassword = _newController.text;
    final confirmPassword = _confirmController.text;
    final oldPasswordError = accountCredentialError(oldPassword, label: '原密码');
    if (oldPasswordError != null) {
      setState(() {
        _error = oldPasswordError;
      });
      return;
    }
    final newPasswordError = passwordStrengthError(newPassword, label: '新密码');
    if (newPasswordError != null) {
      setState(() {
        _error = newPasswordError;
      });
      return;
    }
    final confirmPasswordError = passwordStrengthError(
      confirmPassword,
      label: '确认密码',
    );
    if (confirmPasswordError != null) {
      setState(() {
        _error = confirmPasswordError;
      });
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() {
        _error = '两次输入的新密码不一致';
      });
      return;
    }
    Navigator.of(context).pop(
      _PasswordFormValue(
        oldPassword: oldPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改密码'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _oldController,
              obscureText: true,
              inputFormatters: accountCredentialInputFormatters(),
              decoration: const InputDecoration(
                labelText: '原密码',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newController,
              obscureText: true,
              inputFormatters: accountCredentialInputFormatters(),
              decoration: const InputDecoration(
                labelText: '新密码',
                prefixIcon: Icon(Icons.password_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: true,
              inputFormatters: accountCredentialInputFormatters(),
              decoration: const InputDecoration(
                labelText: '确认新密码',
                prefixIcon: Icon(Icons.verified_user_outlined),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: AppTheme.withPlatformFont(
                    TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

class _PasswordFormValue {
  const _PasswordFormValue({
    required this.oldPassword,
    required this.newPassword,
    required this.confirmPassword,
  });

  final String oldPassword;
  final String newPassword;
  final String confirmPassword;
}

class _DeleteAccountDialog extends StatelessWidget {
  const _DeleteAccountDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('注销账号'),
      content: const Text('注销后，账号中的文件、传输记录、设备和其他信息都会被删除，且无法恢复。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('确认注销'),
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
          child: Text('正在加载账号资料'),
        ),
      ),
    );
  }
}
