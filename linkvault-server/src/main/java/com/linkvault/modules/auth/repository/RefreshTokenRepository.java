package com.linkvault.modules.auth.repository;

import com.linkvault.modules.auth.domain.RefreshTokenEntity;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RefreshTokenRepository extends JpaRepository<RefreshTokenEntity, UUID> {

    Optional<RefreshTokenEntity> findByTokenHash(String tokenHash);

    List<RefreshTokenEntity> findByUserIdAndDeviceIdAndRevokedAtIsNull(UUID userId, UUID deviceId);

    void deleteByExpiresAtBefore(Instant threshold);

    void deleteByUserId(UUID userId);
}
