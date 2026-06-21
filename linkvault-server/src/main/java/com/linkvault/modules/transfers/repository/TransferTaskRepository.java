package com.linkvault.modules.transfers.repository;

import com.linkvault.common.exception.ResourceNotFoundException;
import com.linkvault.modules.transfers.domain.TransferDirection;
import com.linkvault.modules.transfers.domain.TransferTaskEntity;
import com.linkvault.modules.transfers.domain.TransferTaskStatus;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface TransferTaskRepository extends JpaRepository<TransferTaskEntity, UUID> {

    Page<TransferTaskEntity> findByUserIdAndDeviceIdAndDirectionAndHiddenAtIsNullOrderByCreatedAtDesc(
            UUID userId,
            UUID deviceId,
            TransferDirection direction,
            Pageable pageable
    );

    Page<TransferTaskEntity> findByUserIdAndDeviceIdAndDirectionAndStatusAndHiddenAtIsNullOrderByCreatedAtDesc(
            UUID userId,
            UUID deviceId,
            TransferDirection direction,
            TransferTaskStatus status,
            Pageable pageable
    );

    Optional<TransferTaskEntity> findByIdAndUserIdAndDeviceId(UUID id, UUID userId, UUID deviceId);

    Optional<TransferTaskEntity> findByUserIdAndDeviceIdAndSourceIdAndHiddenAtIsNull(
            UUID userId,
            UUID deviceId,
            UUID sourceId
    );

    Optional<TransferTaskEntity> findByUserIdAndSourceIdAndHiddenAtIsNull(UUID userId, UUID sourceId);

    void deleteByUserId(UUID userId);

    List<TransferTaskEntity> findByUserIdAndDeviceIdAndHiddenAtIsNull(UUID userId, UUID deviceId);

    List<TransferTaskEntity> findByUserIdAndDeviceIdAndDirectionAndStatusAndHiddenAtIsNull(
            UUID userId,
            UUID deviceId,
            TransferDirection direction,
            TransferTaskStatus status
    );

    List<TransferTaskEntity> findByUserIdAndDeviceIdAndDirectionAndHiddenAtIsNull(
            UUID userId,
            UUID deviceId,
            TransferDirection direction
    );

    default TransferTaskEntity getByIdAndUserIdAndDeviceId(UUID id, UUID userId, UUID deviceId) {
        return findByIdAndUserIdAndDeviceId(id, userId, deviceId)
                .orElseThrow(() -> new ResourceNotFoundException("Transfer task", id));
    }
}
