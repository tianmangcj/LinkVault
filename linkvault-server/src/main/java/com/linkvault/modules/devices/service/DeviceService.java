package com.linkvault.modules.devices.service;

import com.linkvault.modules.devices.domain.DeviceEntity;
import com.linkvault.modules.devices.domain.DevicePlatform;
import com.linkvault.modules.devices.dto.DeviceVM;
import com.linkvault.modules.devices.dto.RegisterDeviceCmd;
import com.linkvault.modules.devices.repository.DeviceRepository;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DeviceService {
    private final DeviceRepository deviceRepository;

    public DeviceService(DeviceRepository deviceRepository) {
        this.deviceRepository = deviceRepository;
    }

    @Transactional
    public DeviceVM registerOrTouchDevice(RegisterDeviceCmd cmd) {
        DeviceEntity device;
        if (cmd.deviceId() != null) {
            device = deviceRepository.findByIdAndUserId(cmd.deviceId(), cmd.userId())
                    .orElseGet(() -> DeviceEntity.create(
                            cmd.userId(),
                            cmd.deviceName(),
                            DevicePlatform.from(cmd.platform()),
                            cmd.appVersion(),
                            cmd.ipAddress()
                    ));
            device.touch(cmd.deviceName(), DevicePlatform.from(cmd.platform()), cmd.appVersion(), cmd.ipAddress());
        } else {
            device = DeviceEntity.create(
                    cmd.userId(),
                    cmd.deviceName(),
                    DevicePlatform.from(cmd.platform()),
                    cmd.appVersion(),
                    cmd.ipAddress()
            );
        }
        return toVm(deviceRepository.save(device), device.getId());
    }

    @Transactional(readOnly = true)
    public List<DeviceVM> listDevices(UUID userId, UUID currentDeviceId) {
        return deviceRepository.findByUserIdAndRevokedAtIsNullOrderByLastSeenAtDesc(userId)
                .stream()
                .map(device -> toVm(device, currentDeviceId))
                .toList();
    }

    @Transactional(readOnly = true)
    public boolean isDeviceActive(UUID userId, UUID deviceId) {
        return deviceRepository.existsByIdAndUserIdAndRevokedAtIsNull(deviceId, userId);
    }

    @Transactional
    public DeviceVM touchLogin(UUID userId, UUID deviceId) {
        var device = deviceRepository.getByIdAndUserId(deviceId, userId);
        device.touchLogin();
        return toVm(device, deviceId);
    }

    @Transactional
    public void revokeDevice(UUID userId, UUID deviceId) {
        var device = deviceRepository.getByIdAndUserId(deviceId, userId);
        device.revoke(Instant.now());
    }

    public DeviceVM toVm(DeviceEntity device, UUID currentDeviceId) {
        return new DeviceVM(
                device.getId(),
                device.getDeviceName(),
                device.getPlatform().name(),
                device.getAppVersion(),
                device.getLastIp(),
                device.getLastSeenAt(),
                currentDeviceId != null && currentDeviceId.equals(device.getId())
        );
    }
}
