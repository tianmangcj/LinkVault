package com.linkvault.modules.auth.dto;

import java.time.Instant;

public record IssuedToken(
        String token,
        Instant expiresAt
) {
}
