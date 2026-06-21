import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/network/api_exceptions.dart';
import '../../core/network/linkvault_models.dart';

class SlideCaptcha extends StatefulWidget {
  const SlideCaptcha({
    super.key,
    required this.captcha,
    required this.loading,
    required this.checking,
    required this.verified,
    required this.error,
    required this.onRefresh,
    required this.onVerify,
  });

  static const naturalWidth = 310.0;
  static const naturalHeight = 155.0;
  static const pieceWidth = 54.0;
  static const initialOffset = 12.0;

  final CaptchaChallenge? captcha;
  final bool loading;
  final bool checking;
  final bool verified;
  final Object? error;
  final VoidCallback onRefresh;
  final ValueChanged<double> onVerify;

  @override
  State<SlideCaptcha> createState() => _SlideCaptchaState();
}

class _SlideCaptchaState extends State<SlideCaptcha> {
  double _offset = SlideCaptcha.initialOffset;
  String? _token;
  Uint8List? _backgroundBytes;
  Uint8List? _pieceBytes;

  @override
  void initState() {
    super.initState();
    _syncCaptchaImages();
  }

  @override
  void didUpdateWidget(covariant SlideCaptcha oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCaptchaImages();
  }

  void _syncCaptchaImages() {
    final nextToken = widget.captcha?.token;
    if (_token == nextToken) {
      return;
    }
    _token = nextToken;
    _offset = SlideCaptcha.initialOffset;
    _backgroundBytes = _decodeCaptchaImage(widget.captcha?.originalImageBase64);
    _pieceBytes = _decodeCaptchaImage(widget.captcha?.jigsawImageBase64);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = constraints.maxWidth
            .clamp(0.0, SlideCaptcha.naturalWidth)
            .toDouble();
        final imageHeight =
            imageWidth / SlideCaptcha.naturalWidth * SlideCaptcha.naturalHeight;
        final maxOffset = imageWidth - SlideCaptcha.pieceWidth;
        final safeMaxOffset = maxOffset <= 0 ? 1.0 : maxOffset;
        final scaledOffset = _offset.clamp(0.0, safeMaxOffset).toDouble();

        return Center(
          child: SizedBox(
            width: imageWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: imageWidth,
                  height: imageHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_backgroundBytes != null)
                            Image.memory(
                              _backgroundBytes!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          else
                            Center(
                              child: Text(
                                widget.loading ? '正在加载验证码' : '点击刷新验证码',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (_pieceBytes != null && !widget.loading)
                            Positioned(
                              left: scaledOffset,
                              top: 0,
                              bottom: 0,
                              child: Image.memory(
                                _pieceBytes!,
                                fit: BoxFit.contain,
                                gaplessPlayback: true,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: scaledOffset,
                        min: 0,
                        max: safeMaxOffset,
                        onChanged: _enabled
                            ? (value) {
                                setState(() {
                                  _offset = value;
                                });
                              }
                            : null,
                        onChangeEnd: _enabled
                            ? (value) => widget.onVerify(
                                value /
                                    imageWidth *
                                    SlideCaptcha.naturalWidth,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '刷新验证码',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.loading || widget.checking
                          ? null
                          : widget.onRefresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: widget.verified
                            ? colorScheme.primary
                            : widget.error == null
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.error,
                      ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _enabled =>
      widget.captcha != null &&
      !widget.loading &&
      !widget.checking &&
      !widget.verified;

  String get _statusText {
    if (widget.verified) {
      return '验证通过';
    }
    if (widget.checking) {
      return '正在校验';
    }
    if (widget.loading) {
      return '正在加载验证码';
    }
    if (widget.error != null) {
      if (normalizeApiError(widget.error!).message ==
          networkConnectionFailureMessage) {
        return networkConnectionFailureMessage;
      }
      return '验证失败，请重试';
    }
    return '拖动滑块完成验证';
  }
}

Uint8List? _decodeCaptchaImage(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final commaIndex = value.indexOf(',');
  final encoded = commaIndex >= 0 ? value.substring(commaIndex + 1) : value;
  try {
    return base64Decode(encoded);
  } catch (_) {
    return null;
  }
}
