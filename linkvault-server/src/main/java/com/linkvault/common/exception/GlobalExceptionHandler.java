package com.linkvault.common.exception;

import com.linkvault.common.response.ApiResponse;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Void>> handleValidation(MethodArgumentNotValidException exception) {
        var fieldError = exception.getBindingResult().getFieldErrors().stream().findFirst().orElse(null);
        return ResponseEntity
                .status(HttpStatus.BAD_REQUEST)
                .body(ApiResponse.failed(validationCode(fieldError), validationMessage(fieldError)));
    }

    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ApiResponse<Void>> handleBusiness(BusinessException exception) {
        return ResponseEntity
                .status(exception.getStatus())
                .body(ApiResponse.failed(exception.getCode(), localizedMessage(exception)));
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ApiResponse<Void>> handleAccessDenied(AccessDeniedException exception) {
        return ResponseEntity
                .status(HttpStatus.FORBIDDEN)
                .body(ApiResponse.failed("forbidden", "没有权限执行此操作"));
    }

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<ApiResponse<Void>> handleAuthentication(AuthenticationException exception) {
        return ResponseEntity
                .status(HttpStatus.UNAUTHORIZED)
                .body(ApiResponse.failed("unauthorized", "请先登录"));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleUnexpected(Exception exception) {
        return ResponseEntity
                .status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.failed("internal_error", "服务暂时不可用，请稍后重试"));
    }

    private String localizedMessage(BusinessException exception) {
        return switch (exception.getCode()) {
            case "invalid_username" -> "用户名只能包含英文字母和数字，不能包含中文或特殊字符";
            case "invalid_credentials" -> "账号或密码错误";
            case "invalid_captcha" -> "验证码校验失败，请重新完成验证";
            case "name_conflict" -> "名称已存在";
            case "invalid_password" -> "原密码错误";
            case "invalid_image_type" -> "图片类型错误";
            case "quota_exceeded" -> "存储空间不足，请清理后重试";
            case "not_found" -> "内容不存在或已被删除";
            case "forbidden" -> "没有权限执行此操作";
            case "unauthorized" -> "请先登录";
            case "internal_error" -> "服务暂时不可用，请稍后重试";
            case "object_storage_error", "storage_error" -> "存储服务暂时不可用，请稍后重试";
            case "restore_original_path_missing" -> "原位置不可用，请选择新的恢复位置";
            case "upload_paused" -> "上传已暂停，可在传输页面继续";
            case "upload_canceled" -> "上传已取消";
            case "upload_offset_mismatch" -> "上传进度不一致，请重新继续传输";
            case "download_canceled" -> "下载已取消";
            case "download_completed" -> "下载已完成";
            case "validation_error" -> localizedValidationMessage(exception.getMessage());
            default -> "请求失败，请稍后重试";
        };
    }

    private String localizedValidationMessage(String message) {
        if (message == null || message.isBlank()) {
            return "请求内容有误，请检查后重试";
        }
        var normalized = message.toLowerCase();
        if (normalized.contains("passwords do not match")
                || normalized.contains("new passwords do not match")) {
            return "两次输入的密码不一致";
        }
        if (normalized.contains("username is required")) {
            return "请输入用户名";
        }
        return "请求内容有误，请检查后重试";
    }

    private String validationCode(FieldError error) {
        if (error == null) {
            return "validation_error";
        }
        if ("username".equals(error.getField()) && "Pattern".equals(error.getCode())) {
            return "invalid_username";
        }
        return "validation_error";
    }

    private String validationMessage(FieldError error) {
        if (error == null) {
            return "请求内容有误，请检查后重试";
        }
        var field = error.getField();
        var code = error.getCode();
        if ("username".equals(field)) {
            if ("NotBlank".equals(code)) {
                return "请输入用户名";
            }
            if ("Size".equals(code)) {
                return "用户名最多 64 位";
            }
            if ("Pattern".equals(code)) {
                return "用户名只能包含英文字母和数字，不能包含中文或特殊字符";
            }
        }
        if ("account".equals(field) && "NotBlank".equals(code)) {
            return "请输入用户名";
        }
        if ("password".equals(field)) {
            if ("NotBlank".equals(code)) {
                return "请输入密码";
            }
            if ("Size".equals(code)) {
                return "密码至少 8 位，最多 128 位";
            }
        }
        if ("confirmPassword".equals(field) && "NotBlank".equals(code)) {
            return "请确认密码";
        }
        if ("captchaVerification".equals(field) && "NotBlank".equals(code)) {
            return "请先完成滑动验证";
        }
        return "请求内容有误，请检查后重试";
    }
}
