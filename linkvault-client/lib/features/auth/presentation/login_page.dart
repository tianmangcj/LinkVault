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

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 840;
          final compactHeight = constraints.maxHeight < 700;
          final windowsLayout =
              defaultTargetPlatform == TargetPlatform.windows && wide;
          final form = const SizedBox(
            width: _LoginForm.width,
            child: _LoginForm(),
          );

          if (windowsLayout) {
            return Row(
              children: [
                const Spacer(),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: compactHeight ? 14 : 22,
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
                vertical: compactHeight ? 14 : 22,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wide ? 980 : 420,
                  minHeight: wide ? 520 : 0,
                ),
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

class _LoginForm extends StatefulWidget {
  const _LoginForm();

  static const width = SlideCaptcha.naturalWidth + 40;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
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
    _accountController.dispose();
    _passwordController.dispose();
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

  Future<void> _login() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text;
    final captchaVerification = _captchaVerification;
    final usernameValidationError = usernameError(account);
    if (usernameValidationError != null) {
      _showError(usernameValidationError);
      return;
    }
    final passwordError = accountCredentialError(password, label: '密码');
    if (passwordError != null) {
      _showError(passwordError);
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
      await DependenciesScope.of(
        context,
      ).apiClient.login(
        account: account,
        password: password,
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
      _showError(normalizeApiError(error).message);
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
                .clamp(0.0, _LoginForm.width)
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
                      Row(
                        children: [
                          Container(
                            width: 52,
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'LinkVault',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      TextField(
                        controller: _accountController,
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
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitting ? null : _login(),
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
                        onPressed: _submitting ? null : _login,
                        icon: _submitting
                            ? const Icon(Icons.hourglass_empty)
                            : const Icon(Icons.login),
                        label: Text(_submitting ? '登录中' : '登录'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pushReplacementNamed(AppRoute.register.path),
                        child: const Text('创建账号'),
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
