package com.linkvault.modules.users.dto;

import jakarta.validation.constraints.NotBlank;

public record UpdateAvatarRequest(
        @NotBlank String avatarImageData
) {
}
