package com.linkvault.modules.users.dto;

import java.time.Instant;
import java.util.UUID;

public record UserProfileVM(
        UUID id,
        String username,
        String email,
        String displayName,
        String avatarText,
        String avatarImageData,
        String role,
        Instant createdAt
) {
}
