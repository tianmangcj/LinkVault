import 'package:flutter/services.dart';

const int appTextMaxLength = 64;

final RegExp accountCredentialPattern = RegExp(r'^[!-~]+$');
final RegExp usernamePattern = RegExp(r'^[A-Za-z0-9]+$');
final RegExp passwordDigitPattern = RegExp(r'\d');
final RegExp passwordLetterPattern = RegExp(r'[A-Za-z]');

List<TextInputFormatter> textInputFormatters({
  int maxLength = appTextMaxLength,
}) {
  return [LengthLimitingTextInputFormatter(maxLength)];
}

List<TextInputFormatter> accountCredentialInputFormatters({
  int maxLength = appTextMaxLength,
}) {
  return [
    FilteringTextInputFormatter.allow(RegExp(r'[!-~]')),
    LengthLimitingTextInputFormatter(maxLength),
  ];
}

List<TextInputFormatter> usernameInputFormatters({
  int maxLength = appTextMaxLength,
}) {
  return [
    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
    LengthLimitingTextInputFormatter(maxLength),
  ];
}

bool isAccountCredentialText(String value) {
  return value.isNotEmpty && accountCredentialPattern.hasMatch(value);
}

bool isUsernameText(String value) {
  return value.isNotEmpty && usernamePattern.hasMatch(value);
}

String? usernameError(String value) {
  if (value.isEmpty) {
    return '请输入用户名';
  }
  if (value.length > appTextMaxLength) {
    return '用户名最多 64 位';
  }
  if (!isUsernameText(value)) {
    return '用户名只能包含英文字母和数字，不能包含中文或特殊字符';
  }
  return null;
}

String? accountCredentialError(String value, {required String label}) {
  if (value.isEmpty) {
    return '请输入$label';
  }
  if (value.length > appTextMaxLength) {
    return '$label最多 64 位';
  }
  if (!isAccountCredentialText(value)) {
    return '$label只能包含数字、大小写字母和常用可打印特殊字符';
  }
  return null;
}

String? passwordStrengthError(String value, {String label = '密码'}) {
  final formatError = accountCredentialError(value, label: label);
  if (formatError != null) {
    return formatError;
  }
  if (value.length < 8) {
    return '$label至少 8 位';
  }
  if (!passwordDigitPattern.hasMatch(value) ||
      !passwordLetterPattern.hasMatch(value)) {
    return '$label必须同时包含数字和字母';
  }
  return null;
}

String? requiredTextError(String value, {required String label}) {
  if (value.trim().isEmpty) {
    return '请输入$label';
  }
  if (value.length > appTextMaxLength) {
    return '$label最多 64 位';
  }
  return null;
}
