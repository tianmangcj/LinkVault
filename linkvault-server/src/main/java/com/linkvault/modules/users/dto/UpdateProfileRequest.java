package com.linkvault.modules.users.dto;

import jakarta.validation.constraints.Size;

public record UpdateProfileRequest(
        @Size(max = 40) String displayName,
        @Size(max = 4) String avatarText
) {
}
