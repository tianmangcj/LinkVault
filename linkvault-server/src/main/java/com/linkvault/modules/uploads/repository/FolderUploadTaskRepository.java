package com.linkvault.modules.uploads.repository;

import com.linkvault.common.exception.ResourceNotFoundException;
import com.linkvault.modules.uploads.domain.FolderUploadTaskEntity;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface FolderUploadTaskRepository extends JpaRepository<FolderUploadTaskEntity, UUID> {

    Optional<FolderUploadTaskEntity> findByIdAndUserId(UUID id, UUID userId);

    void deleteByUserId(UUID userId);

    default FolderUploadTaskEntity getByIdAndUserId(UUID id, UUID userId) {
        return findByIdAndUserId(id, userId).orElseThrow(() -> new ResourceNotFoundException("Folder upload task", id));
    }
}
