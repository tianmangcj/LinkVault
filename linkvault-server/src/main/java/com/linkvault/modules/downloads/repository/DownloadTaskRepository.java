package com.linkvault.modules.downloads.repository;

import com.linkvault.common.exception.ResourceNotFoundException;
import com.linkvault.modules.downloads.domain.DownloadTaskEntity;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DownloadTaskRepository extends JpaRepository<DownloadTaskEntity, UUID> {

    Optional<DownloadTaskEntity> findByIdAndUserId(UUID id, UUID userId);

    void deleteByUserId(UUID userId);

    default DownloadTaskEntity getByIdAndUserId(UUID id, UUID userId) {
        return findByIdAndUserId(id, userId).orElseThrow(() -> new ResourceNotFoundException("Download task", id));
    }
}
