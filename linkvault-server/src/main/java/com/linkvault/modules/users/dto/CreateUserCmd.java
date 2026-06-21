package com.linkvault.modules.users.dto;

public record CreateUserCmd(
        String username,
        String rawPassword
) {
}
