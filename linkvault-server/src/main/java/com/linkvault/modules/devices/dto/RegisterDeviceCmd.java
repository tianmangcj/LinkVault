package com.linkvault.modules.devices.dto;

import java.util.UUID;

public record RegisterDeviceCmd(
        UUID userId,
        UUID deviceId,
        String deviceName,
        String platform,
        String appVersion,
        String ipAddress
) {
}
