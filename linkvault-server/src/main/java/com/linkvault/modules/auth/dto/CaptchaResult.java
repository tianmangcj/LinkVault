package com.linkvault.modules.auth.dto;

public record CaptchaResult(
        String token,
        String originalImageBase64,
        String jigsawImageBase64,
        String secretKey
) {
}
