package com.linkvault.modules.devices.domain;

import com.linkvault.common.domain.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "devices")
public class DeviceEntity extends BaseEntity {

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "device_name", nullable = false, length = 120)
    private String deviceName;

    @Enumerated(EnumType.STRING)
    @Column(name = "platform", nullable = false, length = 24)
    private DevicePlatform platform;

    @Column(name = "app_version", length = 40)
    private String appVersion;

    @Column(name = "last_ip", length = 80)
    private String lastIp;

    @Column(name = "last_seen_at", nullable = false)
    private Instant lastSeenAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    protected DeviceEntity() {
    }

    private DeviceEntity(UUID userId, String deviceName, DevicePlatform platform, String appVersion, String lastIp) {
        this.userId = userId;
        this.deviceName = normalizeName(deviceName);
        this.platform = platform == null ? DevicePlatform.UNKNOWN : platform;
        this.appVersion = appVersion;
        this.lastIp = lastIp;
        this.lastSeenAt = Instant.now();
    }

    public static DeviceEntity create(
            UUID userId,
            String deviceName,
            DevicePlatform platform,
            String appVersion,
            String lastIp
    ) {
        return new DeviceEntity(userId, deviceName, platform, appVersion, lastIp);
    }

    public void touch(String deviceName, DevicePlatform platform, String appVersion, String lastIp) {
        this.deviceName = normalizeName(deviceName);
        this.platform = platform == null ? DevicePlatform.UNKNOWN : platform;
        this.appVersion = appVersion;
        this.lastIp = lastIp;
        this.lastSeenAt = Instant.now();
        this.revokedAt = null;
    }

    public void touchLogin() {
        this.lastSeenAt = Instant.now();
    }

    public void revoke(Instant now) {
        this.revokedAt = now;
    }

    public UUID getUserId() {
        return userId;
    }

    public String getDeviceName() {
        return deviceName;
    }

    public DevicePlatform getPlatform() {
        return platform;
    }

    public String getAppVersion() {
        return appVersion;
    }

    public String getLastIp() {
        return lastIp;
    }

    public Instant getLastSeenAt() {
        return lastSeenAt;
    }

    public Instant getRevokedAt() {
        return revokedAt;
    }

    private static String normalizeName(String deviceName) {
        if (deviceName == null || deviceName.isBlank()) {
            return "Unknown device";
        }
        return deviceName.trim();
    }
}
