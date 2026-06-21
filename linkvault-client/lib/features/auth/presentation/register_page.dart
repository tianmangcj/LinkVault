import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/di/app_dependencies.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/linkvault_models.dart';
import '../../../shared/widgets/auth_form_theme.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/input_constraints.dart';
import '../../../shared/widgets/slide_captcha.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          final windowsLayout =
              defaultTargetPlatform == TargetPlatform.windows && wide;
          final form = const SizedBox(
            width: _RegisterForm.width,
            child: _RegisterForm(),
          );

          if (windowsLayout) {
            return Row(
              children: [
                const Spacer(),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 22,
                      ),
                      child: AppFeedbackAnchor(child: form),
                    ),
                  ),
                ),
              ],
            );
          }

          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 32 : 20,
                vertical: 22,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 860 : 420),
                child: form,
              ),
            ),
          );
        },
      ),
    );

    final body = defaultTargetPlatform == TargetPlatform.windows
        ? Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/login_background.jpg',
                fit: BoxFit.cover,
              ),
              content,
            ],
          )
        : content;

    return Scaffold(
      body: body,
    );
  }
}

class _RegisterForm extends StatefulWidget {
  const _RegisterForm();

  static const width = SlideCaptcha.naturalWidth + 40;

  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  CaptchaChallenge? _captcha;
  Object? _captchaError;
  String? _captchaVerification;
  bool _loadingCaptcha = true;
  bool _checkingCaptcha = false;
  bool _submitting = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadCaptcha();
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadCaptcha() async {
    setState(() {
      _loadingCaptcha = true;
      _captchaError = null;
      _captchaVerification = null;
    });
    try {
      final captcha = await DependenciesScope.of(context).apiClient.captcha();
      if (!mounted) {
        return;
      }
      setState(() {
        _captcha = captcha;
        _loadingCaptcha = false;
        _captchaVerification = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _captchaError = error;
        _loadingCaptcha = false;
        _captchaVerification = null;
      });
    }
  }

  Future<void> _checkCaptcha(double x) async {
    final captcha = _captcha;
    if (captcha == null || _checkingCaptcha || _loadingCaptcha) {
      return;
    }
    setState(() {
      _checkingCaptcha = true;
      _captchaError = null;
      _captchaVerification = null;
    });
    try {
      final verification = await DependenciesScope.of(context)
          .apiClient
          .checkCaptcha(
            token: captcha.token,
            pointJson: jsonEncode({'x': x.round(), 'y': 5}),
          );
      if (!mounted) {
        return;
      }
      if (verification.captchaVerification.isEmpty) {
        throw const FormatException('验证码校验结果无效');
      }
      setState(() {
        _captchaVerification = verification.captchaVerification;
        _checkingCaptcha = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _captchaError = error;
        _checkingCaptcha = false;
      });
      _showError(_slideCaptchaErrorMessage(error));
      await _loadCaptcha();
    }
  }

  Future<void> _register() async {
    final captchaVerification = _captchaVerification;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (username.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _showError('请填写完整注册信息');
      return;
    }
    final usernameValidationError = usernameError(username);
    if (usernameValidationError != null) {
      _showError(usernameValidationError);
      return;
    }
    final passwordError = passwordStrengthError(password);
    if (passwordError != null) {
      _showError(passwordError);
      return;
    }
    final confirmPasswordError = passwordStrengthError(
      confirmPassword,
      label: '确认密码',
    );
    if (confirmPasswordError != null) {
      _showError(confirmPasswordError);
      return;
    }
    if (password != confirmPassword) {
      _showError('两次输入的密码不一致');
      return;
    }
    if (captchaVerification == null || captchaVerification.isEmpty) {
      _showError('请完成滑动验证');
      return;
    }

    setState(() {
      _submitting = true;
    });
    try {
      await DependenciesScope.of(context).apiClient.register(
        username: username,
        password: password,
        confirmPassword: confirmPassword,
        captchaVerification: captchaVerification,
      );
      if (!mounted) {
        return;
      }
      AppShell.resetNavigationHistory();
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoute.files.path, (route) => false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final apiError = normalizeApiError(error);
      _showError(
        apiError.code == 'name_conflict' ? '用户名已存在，不能注册' : apiError.message,
      );
      await _loadCaptcha();
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  void _showError(String message) {
    showAppNotice(context, message, type: AppNoticeType.error);
  }

  String _slideCaptchaErrorMessage(Object error) {
    return normalizeApiError(error).message.replaceFirst('验证码', '');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AuthFormTheme(
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final formWidth = constraints.maxWidth
                .clamp(0.0, _RegisterForm.width)
                .toDouble();

            return SizedBox(
              width: formWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border.all(color: colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '注册账号',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        inputFormatters: usernameInputFormatters(),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: '密码',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        inputFormatters: accountCredentialInputFormatters(),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _confirmPasswordController,
                        decoration: const InputDecoration(
                          labelText: '确认密码',
                          prefixIcon: Icon(Icons.lock_reset),
                        ),
                        obscureText: true,
                        inputFormatters: accountCredentialInputFormatters(),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      SlideCaptcha(
                        captcha: _captcha,
                        loading: _loadingCaptcha,
                        checking: _checkingCaptcha,
                        verified: _captchaVerification != null,
                        error: _captchaError,
                        onRefresh: _loadCaptcha,
                        onVerify: _checkCaptcha,
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _register,
                        icon: _submitting
                            ? const Icon(Icons.hourglass_empty)
                            : const Icon(Icons.person_add_alt),
                        label: Text(_submitting ? '注册中' : '注册'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pushReplacementNamed(AppRoute.login.path),
                        child: const Text('返回登录'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
