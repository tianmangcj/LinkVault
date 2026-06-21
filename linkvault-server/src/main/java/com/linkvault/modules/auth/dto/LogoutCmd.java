package com.linkvault.modules.auth.dto;

import java.util.UUID;

public record LogoutCmd(
        UUID userId,
        UUID deviceId,
        String refreshToken
) {
}
