package com.linkvault.modules.auth.dto;

public record LoginCmd(
        String account,
        String password,
        String captchaVerification,
        String deviceName,
        String platform,
        String appVersion,
        String ipAddress
) {
}
