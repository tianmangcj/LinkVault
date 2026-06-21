package com.linkvault.modules.devices.dto;

public record ReportDeviceRequest(
        String deviceName,
        String platform,
        String appVersion
) {
}
