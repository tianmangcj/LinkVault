import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const networkConnectionFailureMessage = '网络异常，请稍后重试';
const genericRequestFailureMessage = '请求失败，请稍后重试';

abstract class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  @override
  String toString() => message;
}

class ApiHttpException extends ApiException {
  const ApiHttpException(
    super.message, {
    required super.statusCode,
    super.code,
  });
}

class UnauthorizedApiException extends ApiException {
  const UnauthorizedApiException(super.message, {String? code})
    : super(statusCode: 401, code: code ?? 'unauthorized');
}

class ApiTimeoutException extends ApiException {
  const ApiTimeoutException(super.message);
}

class NetworkApiException extends ApiException {
  const NetworkApiException(super.message);
}

class LocalFileApiException extends ApiException {
  const LocalFileApiException(super.message);
}

class JsonApiException extends ApiException {
  const JsonApiException(super.message);
}

ApiException normalizeApiError(Object error) {
  if (error is ApiException) {
    return _withUserFacingMessage(error);
  }
  if (error is TimeoutException) {
    return const ApiTimeoutException(networkConnectionFailureMessage);
  }
  if (error is SocketException ||
      error is HttpException ||
      error is HandshakeException ||
      error is http.ClientException) {
    return const NetworkApiException(networkConnectionFailureMessage);
  }
  if (error is FileSystemException) {
    return const LocalFileApiException('无法读取或保存内容，请检查权限后重试');
  }
  if (error is PlatformException) {
    if (_isLocalFilePlatformError(error.code)) {
      return const LocalFileApiException('本地操作失败，请重新选择后重试');
    }
  }
  if (error is FormatException || error is TypeError) {
    return const JsonApiException('服务响应异常，请稍后重试');
  }
  return const NetworkApiException(genericRequestFailureMessage);
}

String userFacingErrorMessage(
  String? message, {
  String? code,
  int? statusCode,
  String fallback = genericRequestFailureMessage,
}) {
  final normalized = message?.trim() ?? '';
  final mapped = _mappedErrorMessage(
    code: code,
    message: normalized,
    statusCode: statusCode,
  );
  if (mapped != null) {
    return mapped;
  }
  if (normalized.isEmpty ||
      _looksInternal(normalized) ||
      _containsPathOrSpecificFileName(normalized) ||
      _containsEnglish(normalized)) {
    return fallback;
  }
  return normalized;
}

ApiException _withUserFacingMessage(ApiException error) {
  final message = userFacingErrorMessage(
    error.message,
    code: error.code,
    statusCode: error.statusCode,
  );
  if (message == error.message) {
    return error;
  }
  if (error is UnauthorizedApiException) {
    return UnauthorizedApiException(message, code: error.code);
  }
  if (error is ApiTimeoutException) {
    return ApiTimeoutException(message);
  }
  if (error is NetworkApiException) {
    return NetworkApiException(message);
  }
  if (error is LocalFileApiException) {
    return LocalFileApiException(message);
  }
  if (error is JsonApiException) {
    return JsonApiException(message);
  }
  return ApiHttpException(
    message,
    statusCode: error.statusCode ?? 0,
    code: error.code,
  );
}

String? _mappedErrorMessage({
  required String? code,
  required String message,
  required int? statusCode,
}) {
  final lower = message.toLowerCase();
  if (lower.contains('invalid username') ||
      lower.contains('username may only contain') ||
      lower.contains('用户名只能')) {
    return '用户名只能包含英文字母和数字，不能包含中文或特殊字符';
  }
  if (lower.contains('invalid account or password')) {
    return '账号或密码错误';
  }
  if (lower.contains('请先完成滑动验证') ||
      lower.contains('captcha verification is required')) {
    return '请先完成滑动验证';
  }
  if (lower.contains('invalid captcha') ||
      lower.contains('captcha verification') ||
      lower.contains('验证码') ||
      lower.contains('滑动验证')) {
    return '验证码校验失败，请重新完成验证';
  }
  if (lower.contains('passwords do not match') ||
      lower.contains('new passwords do not match')) {
    return '两次输入的密码不一致';
  }
  if (lower.contains('old password is incorrect')) {
    return '原密码错误';
  }
  if (lower.contains('username already exists')) {
    return '用户名已存在';
  }
  if (lower.contains('avatar')) {
    return '图片类型错误';
  }
  if (lower.contains('quota exceeded') ||
      lower.contains('storage quota exceeded')) {
    return '存储空间不足，请清理后重试';
  }
  if (lower.contains('same name already exists')) {
    return '名称已存在';
  }
  if (lower.contains('download canceled')) {
    return '下载已取消';
  }
  if (lower.contains('download paused')) {
    return '下载已暂停，可在传输页面继续';
  }
  if (lower.contains('download completed') ||
      lower.contains('already completed')) {
    return '任务已完成';
  }
  if (lower.contains('upload paused')) {
    return '上传已暂停，可在传输页面继续';
  }
  if (lower.contains('upload canceled')) {
    return '上传已取消';
  }
  if (lower.contains('offset')) {
    return '传输进度不一致，请重新继续传输';
  }
  if (lower.contains('not found') || lower.contains('not active')) {
    return '内容不存在或已被删除';
  }
  if (lower.contains('access denied')) {
    return '没有权限执行此操作';
  }
  if (lower.contains('authentication required') ||
      lower.contains('invalid access token') ||
      lower.contains('access token expired') ||
      lower.contains('invalid refresh token') ||
      lower.contains('token')) {
    return '登录状态已失效，请重新登录';
  }
  if (lower.contains('device is no longer active')) {
    return '当前设备已失效，请重新登录';
  }

  return switch (code) {
    'invalid_username' => '用户名只能包含英文字母和数字，不能包含中文或特殊字符',
    'invalid_credentials' => '账号或密码错误',
    'invalid_captcha' => '验证码校验失败，请重新完成验证',
    'name_conflict' => '名称已存在',
    'invalid_password' => '原密码错误',
    'invalid_image_type' => '图片类型错误',
    'quota_exceeded' => '存储空间不足，请清理后重试',
    'not_found' => '内容不存在或已被删除',
    'forbidden' => '没有权限执行此操作',
    'unauthorized' => '登录状态已失效，请重新登录',
    'internal_error' => '服务暂时不可用，请稍后重试',
    'object_storage_error' || 'storage_error' => '存储服务暂时不可用，请稍后重试',
    'restore_original_path_missing' => '原位置不可用，请选择新的恢复位置',
    'upload_paused' => '上传已暂停，可在传输页面继续',
    'upload_canceled' => '上传已取消',
    'upload_offset_mismatch' => '上传进度不一致，请重新继续传输',
    'download_canceled' => '下载已取消',
    'download_completed' => '下载已完成',
    'validation_error' when _containsEnglish(message) => '请求内容有误，请检查后重试',
    _ when statusCode != null && statusCode >= 500 => '服务暂时不可用，请稍后重试',
    _ => null,
  };
}

bool _containsEnglish(String value) {
  return RegExp(r'[A-Za-z]').hasMatch(value);
}

bool _looksInternal(String value) {
  final lower = value.toLowerCase();
  return lower.contains('exception') ||
      lower.contains('stack trace') ||
      lower.contains('nullpointer') ||
      lower.contains('illegalstate') ||
      lower.contains('illegalargument') ||
      lower.contains('runtimeexception') ||
      lower.contains('com.linkvault') ||
      lower.contains('org.springframework') ||
      lower.contains('java.') ||
      lower.contains('server returned') ||
      lower.contains('data object') ||
      lower.contains('data list') ||
      lower.contains('data 对象') ||
      lower.contains('data 列表');
}

bool _containsPathOrSpecificFileName(String value) {
  return RegExp(r'(^|[\s：:])([A-Za-z]:\\|\\\\|/|content://)').hasMatch(value) ||
      RegExp(
        r'\b[^，。！？\s\\/]+\.(zip|7z|rar|txt|pdf|doc|docx|xls|xlsx|ppt|pptx|png|jpg|jpeg|gif|webp|mp4|mov|avi|mkv|apk|ipa|exe|dmg|part)\b',
        caseSensitive: false,
      ).hasMatch(value);
}

bool _isLocalFilePlatformError(String code) {
  return code == 'open_failed' ||
      code == 'write_failed' ||
      code == 'close_failed' ||
      code == 'cancel_failed' ||
      code == 'delete_failed' ||
      code == 'create_folder_failed' ||
      code == 'download_failed' ||
      code == 'upload_failed';
}
