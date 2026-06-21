package com.linkvault.modules.users.repository;

import com.linkvault.common.exception.ResourceNotFoundException;
import com.linkvault.modules.users.domain.UserEntity;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<UserEntity, UUID> {

    Optional<UserEntity> findByUsernameIgnoreCase(String username);

    Optional<UserEntity> findByEmailIgnoreCase(String email);

    boolean existsByUsernameIgnoreCase(String username);

    boolean existsByEmailIgnoreCase(String email);

    default UserEntity getByIdOrThrow(UUID userId) {
        return findById(userId).orElseThrow(() -> new ResourceNotFoundException("User", userId));
    }

    default Optional<UserEntity> findByAccount(String account) {
        if (account == null || account.isBlank()) {
            return Optional.empty();
        }
        var normalized = account.trim();
        var byUsername = findByUsernameIgnoreCase(normalized);
        if (byUsername.isPresent()) {
            return byUsername;
        }
        return findByEmailIgnoreCase(normalized);
    }
}
