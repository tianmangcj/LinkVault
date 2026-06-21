package com.linkvault.modules.devices.domain;

public enum DevicePlatform {
    ANDROID,
    WINDOWS,
    IOS,
    MACOS,
    LINUX,
    WEB,
    UNKNOWN;

    public static DevicePlatform from(String value) {
        if (value == null || value.isBlank()) {
            return UNKNOWN;
        }
        try {
            return DevicePlatform.valueOf(value.trim().toUpperCase());
        } catch (IllegalArgumentException ignored) {
            return UNKNOWN;
        }
    }
}
