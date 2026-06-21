package com.linkvault.modules.storage.repository;

import com.linkvault.common.exception.ResourceNotFoundException;
import com.linkvault.modules.storage.domain.StorageObjectEntity;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface StorageObjectRepository extends JpaRepository<StorageObjectEntity, UUID> {

    Optional<StorageObjectEntity> findFirstBySha256AndSizeBytesAndPendingDeleteAtIsNull(String sha256, long sizeBytes);

    default StorageObjectEntity getByIdOrThrow(UUID id) {
        return findById(id).orElseThrow(() -> new ResourceNotFoundException("Storage object", id));
    }
}
