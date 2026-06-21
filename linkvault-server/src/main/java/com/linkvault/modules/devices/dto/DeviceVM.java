package com.linkvault.modules.devices.dto;

import java.time.Instant;
import java.util.UUID;

public record DeviceVM(
        UUID id,
        String deviceName,
        String platform,
        String appVersion,
        String lastIp,
        Instant lastSeenAt,
        boolean current
) {
}
