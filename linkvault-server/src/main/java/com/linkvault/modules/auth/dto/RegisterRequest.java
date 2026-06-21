package com.linkvault.modules.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record RegisterRequest(
        @NotBlank @Size(max = 64) @Pattern(regexp = "^[A-Za-z0-9]+$") String username,
        @NotBlank @Size(min = 8, max = 128) String password,
        @NotBlank String confirmPassword,
        @NotBlank String captchaVerification,
        String deviceName,
        String platform,
        String appVersion
) {
}
