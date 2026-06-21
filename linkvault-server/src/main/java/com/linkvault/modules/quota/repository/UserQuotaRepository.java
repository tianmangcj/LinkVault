package com.linkvault.modules.quota.repository;

import com.linkvault.common.exception.ResourceNotFoundException;
import com.linkvault.modules.quota.domain.UserQuotaEntity;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserQuotaRepository extends JpaRepository<UserQuotaEntity, UUID> {

    Optional<UserQuotaEntity> findByUserId(UUID userId);

    void deleteByUserId(UUID userId);

    default UserQuotaEntity getByUserId(UUID userId) {
        return findByUserId(userId).orElseThrow(() -> new ResourceNotFoundException("User quota", userId));
    }
}
