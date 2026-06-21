package com.linkvault.modules.uploads.repository;

import com.linkvault.common.exception.ResourceNotFoundException;
import com.linkvault.modules.uploads.domain.UploadTaskEntity;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UploadTaskRepository extends JpaRepository<UploadTaskEntity, UUID> {

    Optional<UploadTaskEntity> findByIdAndUserId(UUID id, UUID userId);

    void deleteByUserId(UUID userId);

    default UploadTaskEntity getByIdAndUserId(UUID id, UUID userId) {
        return findByIdAndUserId(id, userId).orElseThrow(() -> new ResourceNotFoundException("Upload task", id));
    }
}
