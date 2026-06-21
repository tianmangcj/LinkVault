package com.linkvault.modules.auth.dto;

import java.time.Instant;

public record IssuedRefreshToken(
        String token,
        String tokenHash,
        Instant expiresAt
) {
}
