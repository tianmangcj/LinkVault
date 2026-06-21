package com.linkvault.modules.recyclebin.service;

import com.linkvault.common.exception.BusinessException;
import com.linkvault.common.response.PageResponse;
import com.linkvault.modules.files.domain.FileNodeEntity;
import com.linkvault.modules.files.domain.FileNodeStatus;
import com.linkvault.modules.files.domain.FileNodeType;
import com.linkvault.modules.files.dto.FileNodeVM;
import com.linkvault.modules.files.repository.FileNodeRepository;
import com.linkvault.modules.files.service.FileService;
import com.linkvault.modules.quota.service.QuotaService;
import java.time.Duration;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RecycleBinService {
    public static final String ORIGINAL_PATH_MISSING_CODE = "restore_original_path_missing";
    public static final Duration RECYCLE_BIN_RETENTION = Duration.ofDays(10);

    private final FileNodeRepository fileNodeRepository;
    private final FileService fileService;
    private final QuotaService quotaService;

    public RecycleBinService(
            FileNodeRepository fileNodeRepository,
            FileService fileService,
            QuotaService quotaService
    ) {
        this.fileNodeRepository = fileNodeRepository;
        this.fileService = fileService;
        this.quotaService = quotaService;
    }

    @Transactional(readOnly = true)
    public PageResponse<FileNodeVM> list(UUID userId, int page, int perPage) {
        var nodes = fileNodeRepository.findRecycleBinRoots(
                userId,
                FileNodeStatus.RECYCLED,
                PageRequest.of(Math.max(0, page - 1), Math.max(1, Math.min(perPage, 100)), Sort.by("recycledAt").descending())
        );
        return PageResponse.from(nodes, fileService::toVm);
    }

    @Transactional
    public FileNodeVM restore(UUID userId, UUID fileId, boolean useOriginalPath, UUID parentId) {
        var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
        if (node.getStatus() != FileNodeStatus.RECYCLED) {
            throw new BusinessException("validation_error", "File is not in recycle bin", HttpStatus.BAD_REQUEST);
        }
        if (useOriginalPath) {
            ensureOriginalParentActive(userId, node);
            ensureRestoreNameAvailable(userId, node.getParentId(), node.getName());
        } else {
            ensureRestoreParent(userId, parentId);
            ensureRestoreNameAvailable(userId, parentId, node.getName());
            node.moveTo(parentId);
        }
        restoreRecursive(userId, node, node.getRecycledAt());
        return fileService.toVm(node);
    }

    @Transactional
    public void purgeOne(UUID userId, UUID fileId) {
        var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
        purgeRecursive(userId, node, node.getRecycledAt(), Instant.now());
    }

    @Transactional
    public void empty(UUID userId) {
        var now = Instant.now();
        fileNodeRepository.findRecycleBinRoots(userId, FileNodeStatus.RECYCLED)
                .forEach(node -> purgeRecursive(userId, node, node.getRecycledAt(), now));
    }

    @Scheduled(cron = "0 0 3 * * *")
    @Transactional
    public void purgeExpired() {
        var now = Instant.now();
        var cutoff = now.minus(RECYCLE_BIN_RETENTION);
        fileNodeRepository.findExpiredRecycleBinRoots(FileNodeStatus.RECYCLED, cutoff)
                .forEach(node -> purgeRecursive(node.getUserId(), node, node.getRecycledAt(), now));
    }

    private void restoreRecursive(UUID userId, FileNodeEntity node, Instant recycledAt) {
        node.restore();
        fileNodeRepository.findByUserIdAndParentIdAndStatus(userId, node.getId(), FileNodeStatus.RECYCLED)
                .stream()
                .filter(child -> Objects.equals(child.getRecycledAt(), recycledAt))
                .forEach(child -> restoreRecursive(userId, child, recycledAt));
    }

    private void ensureOriginalParentActive(UUID userId, FileNodeEntity node) {
        ensureFolderPathActive(
                userId,
                node.getParentId(),
                ORIGINAL_PATH_MISSING_CODE,
                "Original path is unavailable, choose another restore location",
                HttpStatus.CONFLICT
        );
    }

    private void ensureRestoreParent(UUID userId, UUID parentId) {
        ensureFolderPathActive(
                userId,
                parentId,
                "validation_error",
                "Restore parent is invalid",
                HttpStatus.BAD_REQUEST
        );
    }

    private void ensureFolderPathActive(
            UUID userId,
            UUID parentId,
            String errorCode,
            String errorMessage,
            HttpStatus status
    ) {
        var currentParentId = parentId;
        while (currentParentId != null) {
            var parent = fileNodeRepository.findByIdAndUserId(currentParentId, userId)
                    .orElseThrow(() -> new BusinessException(errorCode, errorMessage, status));
            if (parent.getStatus() != FileNodeStatus.ACTIVE || parent.getType() != FileNodeType.FOLDER) {
                throw new BusinessException(errorCode, errorMessage, status);
            }
            currentParentId = parent.getParentId();
        }
    }

    private void ensureRestoreNameAvailable(UUID userId, UUID parentId, String name) {
        boolean exists = parentId == null
                ? fileNodeRepository.existsByUserIdAndParentIdIsNullAndStatusAndNameIgnoreCase(
                        userId,
                        FileNodeStatus.ACTIVE,
                        name
                )
                : fileNodeRepository.existsByUserIdAndParentIdAndStatusAndNameIgnoreCase(
                        userId,
                        parentId,
                        FileNodeStatus.ACTIVE,
                        name
                );
        if (exists) {
            throw new BusinessException("name_conflict", "A file with the same name already exists", HttpStatus.CONFLICT);
        }
    }

    private void purgeRecursive(UUID userId, FileNodeEntity node, Instant recycledAt, Instant now) {
        if (node.getStatus() == FileNodeStatus.PURGED) {
            return;
        }
        if (node.getType() == FileNodeType.FOLDER) {
            fileNodeRepository.findByUserIdAndParentIdAndStatus(userId, node.getId(), FileNodeStatus.RECYCLED)
                    .stream()
                    .filter(child -> Objects.equals(child.getRecycledAt(), recycledAt))
                    .forEach(child -> purgeRecursive(userId, child, recycledAt, now));
        } else {
            quotaService.releaseUsedBytes(userId, node.getSizeBytes());
        }
        node.purge(now);
    }
}
