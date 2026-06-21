package com.linkvault.modules.auth.dto;

public record CaptchaResponse(
        String token,
        String originalImageBase64,
        String jigsawImageBase64,
        String secretKey
) {
}
