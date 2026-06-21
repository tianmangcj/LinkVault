package com.linkvault.modules.users.dto;

public record UpdateProfileCmd(
        String displayName,
        String avatarText
) {
}
