package com.linkvault.modules.auth.dto;

import com.linkvault.modules.devices.dto.DeviceVM;
import com.linkvault.modules.users.dto.UserProfileVM;
import java.time.Instant;

public record AuthResponse(
        String accessToken,
        String refreshToken,
        Instant accessTokenExpiresAt,
        Instant refreshTokenExpiresAt,
        UserProfileVM user,
        DeviceVM device
) {
}
