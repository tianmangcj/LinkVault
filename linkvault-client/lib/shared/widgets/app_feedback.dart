import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../core/network/api_exceptions.dart';

enum AppNoticeType { info, success, warning, error }

const connectionFailureSnackBarMessage = '连接失败，请稍微重试';

bool _noticeDialogOpen = false;
DateTime? _lastCompactSnackBarAt;
String? _lastCompactSnackBarMessage;

class AppFeedbackAnchor extends StatefulWidget {
  const AppFeedbackAnchor({
    required this.child,
    this.windowsSnackBarBottomMargin = 24,
    super.key,
  });

  final Widget child;
  final double windowsSnackBarBottomMargin;

  @override
  State<AppFeedbackAnchor> createState() => _AppFeedbackAnchorState();
}

class _AppFeedbackAnchorState extends State<AppFeedbackAnchor> {
  final _anchorKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return _AppFeedbackAnchorScope(
      anchorKey: _anchorKey,
      windowsSnackBarBottomMargin: widget.windowsSnackBarBottomMargin,
      child: KeyedSubtree(key: _anchorKey, child: widget.child),
    );
  }
}

class _AppFeedbackAnchorScope extends InheritedWidget {
  const _AppFeedbackAnchorScope({
    required this.anchorKey,
    required this.windowsSnackBarBottomMargin,
    required super.child,
  });

  final GlobalKey anchorKey;
  final double windowsSnackBarBottomMargin;

  @override
  bool updateShouldNotify(_AppFeedbackAnchorScope oldWidget) {
    return anchorKey != oldWidget.anchorKey ||
        windowsSnackBarBottomMargin != oldWidget.windowsSnackBarBottomMargin;
  }
}

void showCompactAppSnackBar(BuildContext context, String message) {
  if (!context.mounted || message.trim().isEmpty) {
    return;
  }
  final normalized = message.trim();
  final textStyle = AppTheme.withPlatformFont(
    const TextStyle(color: Colors.white, fontSize: 14, height: 1.2),
  );
  final textPainter = TextPainter(
    text: TextSpan(text: normalized, style: textStyle),
    maxLines: 1,
    textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
  )..layout();
  final maxSnackBarWidth = (MediaQuery.sizeOf(context).width - 32).clamp(
    96.0,
    420.0,
  );
  final snackBarWidth = (textPainter.width + 28).clamp(
    64.0,
    maxSnackBarWidth,
  );
  final windowsMargin = _windowsSnackBarMargin(
    context,
    snackBarWidth.toDouble(),
  );
  final now = DateTime.now();
  if (_lastCompactSnackBarMessage == normalized &&
      _lastCompactSnackBarAt != null &&
      now.difference(_lastCompactSnackBarAt!) < const Duration(seconds: 1)) {
    return;
  }
  _lastCompactSnackBarMessage = normalized;
  _lastCompactSnackBarAt = now;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          normalized,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.visible,
          style: textStyle,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        backgroundColor: Colors.black,
        behavior: SnackBarBehavior.floating,
        width: windowsMargin == null ? snackBarWidth.toDouble() : null,
        margin: windowsMargin,
        duration: const Duration(seconds: 1),
      ),
    );
}

EdgeInsetsGeometry? _windowsSnackBarMargin(
  BuildContext context,
  double snackBarWidth,
) {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return null;
  }
  final scopeElement = context.getElementForInheritedWidgetOfExactType<
      _AppFeedbackAnchorScope>();
  final scope = scopeElement?.widget;
  if (scope is! _AppFeedbackAnchorScope) {
    return null;
  }
  final anchorContext = scope.anchorKey.currentContext;
  final anchorBox = anchorContext?.findRenderObject();
  if (anchorBox is! RenderBox || !anchorBox.hasSize) {
    return null;
  }

  final screenWidth = MediaQuery.sizeOf(context).width;
  final anchorOrigin = anchorBox.localToGlobal(Offset.zero);
  final anchorCenterX = anchorOrigin.dx + anchorBox.size.width / 2;
  const edgeMargin = 16.0;
  final maxLeft = screenWidth - snackBarWidth - edgeMargin;
  final left = (anchorCenterX - snackBarWidth / 2).clamp(
    edgeMargin,
    maxLeft < edgeMargin ? edgeMargin : maxLeft,
  );
  final right = (screenWidth - left - snackBarWidth).clamp(
    edgeMargin,
    screenWidth,
  );
  return EdgeInsets.fromLTRB(
    left.toDouble(),
    0,
    right.toDouble(),
    scope.windowsSnackBarBottomMargin,
  );
}

bool isNetworkConnectionFailure(Object error) {
  return normalizeApiError(error).message == networkConnectionFailureMessage;
}

void showNetworkConnectionFailureSnackBar(BuildContext context) {
  showCompactAppSnackBar(context, connectionFailureSnackBarMessage);
}

Future<bool> showAppConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.warning_amber_outlined,
  bool destructive = true,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

void showAppNotice(
  BuildContext context,
  String message, {
  AppNoticeType type = AppNoticeType.info,
  String? title,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  if (!context.mounted || message.trim().isEmpty) {
    return;
  }
  final rawMessage = message.trim();
  final resolvedType = type == AppNoticeType.info
      ? noticeTypeForMessage(rawMessage)
      : type;
  final normalizedMessage =
      resolvedType == AppNoticeType.error ||
          resolvedType == AppNoticeType.warning
      ? userFacingErrorMessage(rawMessage)
      : rawMessage;

  if (resolvedType == AppNoticeType.info ||
      resolvedType == AppNoticeType.success) {
    return;
  }

  if (normalizedMessage == networkConnectionFailureMessage) {
    showNetworkConnectionFailureSnackBar(context);
    return;
  }

  if (_noticeDialogOpen) {
    return;
  }
  _noticeDialogOpen = true;

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: title == null ? null : Text(title),
        content: Text(normalizedMessage),
        actions: [
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onAction();
              },
              child: Text(actionLabel),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      );
    },
  ).whenComplete(() {
    _noticeDialogOpen = false;
  });
}

AppNoticeType noticeTypeForMessage(String message) {
  final normalized = message.trim();
  if (normalized.isEmpty) {
    return AppNoticeType.info;
  }

  const warningHints = [
    '一次最多',
    '当前平台暂不支持',
    '未选择',
    '尚未',
    '请填写',
    '请完整',
    '请先',
    '重试',
    '最多',
    '至少',
    '必须',
    '只能包含',
    '不一致',
    '不能',
    '不支持',
  ];
  if (warningHints.any(normalized.contains)) {
    return AppNoticeType.warning;
  }

  const errorHints = [
    '失败',
    '错误',
    '无法',
    '超时',
    '异常',
    '不存在',
    '冲突',
    '无效',
    '已失效',
    '请先登录',
    '连接',
  ];
  if (errorHints.any(normalized.contains)) {
    return AppNoticeType.error;
  }

  const successHints = [
    '已',
    '成功',
    '完成',
    '创建',
    '删除',
    '重命名',
    '修改',
    '恢复',
    '上传',
    '下载',
    '继续',
    '暂停',
  ];
  if (successHints.any((hint) => normalized.startsWith(hint)) ||
      normalized.contains('成功') ||
      normalized.contains('完成')) {
    return AppNoticeType.success;
  }

  return AppNoticeType.info;
}
