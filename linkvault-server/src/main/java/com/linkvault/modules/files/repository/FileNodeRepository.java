package com.linkvault.modules.files.repository;

import com.linkvault.common.exception.ResourceNotFoundException;
import com.linkvault.modules.files.domain.FileNodeEntity;
import com.linkvault.modules.files.domain.FileNodeStatus;
import com.linkvault.modules.files.domain.FileNodeType;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface FileNodeRepository extends JpaRepository<FileNodeEntity, UUID> {

    Page<FileNodeEntity> findByUserIdAndParentIdAndStatus(UUID userId, UUID parentId, FileNodeStatus status, Pageable pageable);

    Page<FileNodeEntity> findByUserIdAndParentIdIsNullAndStatus(UUID userId, FileNodeStatus status, Pageable pageable);

    Page<FileNodeEntity> findByUserIdAndParentIdAndTypeAndStatus(
            UUID userId,
            UUID parentId,
            FileNodeType type,
            FileNodeStatus status,
            Pageable pageable
    );

    Page<FileNodeEntity> findByUserIdAndParentIdIsNullAndTypeAndStatus(
            UUID userId,
            FileNodeType type,
            FileNodeStatus status,
            Pageable pageable
    );

    Page<FileNodeEntity> findByUserIdAndStatusAndNameContainingIgnoreCase(
            UUID userId,
            FileNodeStatus status,
            String keyword,
            Pageable pageable
    );

    List<FileNodeEntity> findAllByUserIdAndStatusAndNameContainingIgnoreCase(
            UUID userId,
            FileNodeStatus status,
            String keyword
    );

    Page<FileNodeEntity> findByUserIdAndStatus(UUID userId, FileNodeStatus status, Pageable pageable);

    List<FileNodeEntity> findByUserId(UUID userId);

    @Query("""
            select node
            from FileNodeEntity node
            where node.userId = :userId
              and node.status = :status
              and (
                  node.parentId is null
                  or not exists (
                      select parent.id
                      from FileNodeEntity parent
                      where parent.id = node.parentId
                        and parent.userId = node.userId
                        and parent.status = :status
                        and parent.recycledAt = node.recycledAt
                  )
              )
            """)
    Page<FileNodeEntity> findRecycleBinRoots(UUID userId, FileNodeStatus status, Pageable pageable);

    @Query("""
            select node
            from FileNodeEntity node
            where node.userId = :userId
              and node.status = :status
              and (
                  node.parentId is null
                  or not exists (
                      select parent.id
                      from FileNodeEntity parent
                      where parent.id = node.parentId
                        and parent.userId = node.userId
                        and parent.status = :status
                        and parent.recycledAt = node.recycledAt
                  )
              )
            """)
    List<FileNodeEntity> findRecycleBinRoots(UUID userId, FileNodeStatus status);

    @Query("""
            select node
            from FileNodeEntity node
            where node.status = :status
              and node.recycledAt is not null
              and node.recycledAt <= :cutoff
              and (
                  node.parentId is null
                  or not exists (
                      select parent.id
                      from FileNodeEntity parent
                      where parent.id = node.parentId
                        and parent.userId = node.userId
                        and parent.status = :status
                        and parent.recycledAt = node.recycledAt
                  )
              )
            order by node.recycledAt asc
            """)
    List<FileNodeEntity> findExpiredRecycleBinRoots(FileNodeStatus status, Instant cutoff);

    List<FileNodeEntity> findByUserIdAndParentIdAndStatus(UUID userId, UUID parentId, FileNodeStatus status);

    List<FileNodeEntity> findByUserIdAndParentIdIsNullAndStatus(UUID userId, FileNodeStatus status);

    boolean existsByUserIdAndParentIdAndStatusAndNameIgnoreCase(
            UUID userId,
            UUID parentId,
            FileNodeStatus status,
            String name
    );

    boolean existsByUserIdAndParentIdIsNullAndStatusAndNameIgnoreCase(
            UUID userId,
            FileNodeStatus status,
            String name
    );

    Optional<FileNodeEntity> findByIdAndUserId(UUID id, UUID userId);

    void deleteByUserId(UUID userId);

    default FileNodeEntity getByIdAndUserId(UUID id, UUID userId) {
        return findByIdAndUserId(id, userId).orElseThrow(() -> new ResourceNotFoundException("File node", id));
    }
}
