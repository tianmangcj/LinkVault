package com.linkvault.modules.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record LoginRequest(
        @NotBlank String account,
        @NotBlank String password,
        @NotBlank String captchaVerification,
        String deviceName,
        String platform,
        String appVersion
) {
}
