package com.linkvault.modules.auth.dto;

public record LogoutRequest(
        String refreshToken
) {
}
