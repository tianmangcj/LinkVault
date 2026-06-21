package com.linkvault.modules.devices.repository;

import com.linkvault.common.exception.ResourceNotFoundException;
import com.linkvault.modules.devices.domain.DeviceEntity;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DeviceRepository extends JpaRepository<DeviceEntity, UUID> {

    List<DeviceEntity> findByUserIdAndRevokedAtIsNullOrderByLastSeenAtDesc(UUID userId);

    Optional<DeviceEntity> findByIdAndUserId(UUID id, UUID userId);

    boolean existsByIdAndUserIdAndRevokedAtIsNull(UUID id, UUID userId);

    void deleteByUserId(UUID userId);

    default DeviceEntity getByIdAndUserId(UUID id, UUID userId) {
        return findByIdAndUserId(id, userId)
                .orElseThrow(() -> new ResourceNotFoundException("Device", id));
    }
}
