package com.linkvault.modules.auth.dto;

public record RegisterCmd(
        String username,
        String password,
        String confirmPassword,
        String captchaVerification,
        String deviceName,
        String platform,
        String appVersion,
        String ipAddress
) {
}
