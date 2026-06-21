package com.linkvault.modules.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record CaptchaCheckRequest(
        @NotBlank String token,
        @NotBlank String pointJson
) {
}
