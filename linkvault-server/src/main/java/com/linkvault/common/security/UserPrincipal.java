package com.linkvault.common.security;

import java.util.UUID;

public record UserPrincipal(
        UUID userId,
        UUID deviceId,
        String username,
        String role
) {
}
