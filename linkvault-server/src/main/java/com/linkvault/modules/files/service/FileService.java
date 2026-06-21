package com.linkvault.modules.files.service;

import com.linkvault.common.exception.BusinessException;
import com.linkvault.common.response.PageResponse;
import com.linkvault.modules.files.domain.FileNodeEntity;
import com.linkvault.modules.files.domain.FileNodeStatus;
import com.linkvault.modules.files.domain.FileNodeType;
import com.linkvault.modules.files.dto.BatchFileActionItemVM;
import com.linkvault.modules.files.dto.BatchFileActionResponse;
import com.linkvault.modules.files.dto.CreateFileNodeCmd;
import com.linkvault.modules.files.dto.CreateFolderCmd;
import com.linkvault.modules.files.dto.FileNodeVM;
import com.linkvault.modules.files.dto.ListFilesQuery;
import com.linkvault.modules.files.repository.FileNodeRepository;
import com.linkvault.modules.storage.service.StorageObjectService;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FileService {
    public static final int MAX_BATCH_ITEMS = 10;

    private final FileNodeRepository fileNodeRepository;
    private final StorageObjectService storageObjectService;

    public FileService(FileNodeRepository fileNodeRepository, StorageObjectService storageObjectService) {
        this.fileNodeRepository = fileNodeRepository;
        this.storageObjectService = storageObjectService;
    }

    @Transactional(readOnly = true)
    public PageResponse<FileNodeVM> listFiles(ListFilesQuery query) {
        var pageable = pageRequest(query.page(), query.perPage());
        Page<FileNodeEntity> page;
        if (query.parentId() == null) {
            page = query.type() == null
                    ? fileNodeRepository.findByUserIdAndParentIdIsNullAndStatus(query.userId(), FileNodeStatus.ACTIVE, pageable)
                    : fileNodeRepository.findByUserIdAndParentIdIsNullAndTypeAndStatus(query.userId(), query.type(), FileNodeStatus.ACTIVE, pageable);
        } else {
            page = query.type() == null
                    ? fileNodeRepository.findByUserIdAndParentIdAndStatus(query.userId(), query.parentId(), FileNodeStatus.ACTIVE, pageable)
                    : fileNodeRepository.findByUserIdAndParentIdAndTypeAndStatus(query.userId(), query.parentId(), query.type(), FileNodeStatus.ACTIVE, pageable);
        }
        return PageResponse.from(page, this::toVm);
    }

    @Transactional(readOnly = true)
    public PageResponse<FileNodeVM> search(UUID userId, String keyword, String scope, UUID parentId, int page, int perPage) {
        var searchScope = parseSearchScope(scope);
        if (parentId != null) {
            ensureParentFolder(userId, parentId);
        }
        var nodes = fileNodeRepository.findAllByUserIdAndStatusAndNameContainingIgnoreCase(
                userId,
                FileNodeStatus.ACTIVE,
                keyword == null ? "" : keyword.trim()
        ).stream()
                .filter(node -> matchesSearchScope(userId, node, searchScope, parentId))
                .sorted(fileNodeComparator())
                .toList();
        return PageResponse.from(pageFromList(nodes, page, perPage), this::toVm);
    }

    @Transactional(readOnly = true)
    public FileNodeVM getFile(UUID userId, UUID fileId) {
        return toVm(fileNodeRepository.getByIdAndUserId(fileId, userId));
    }

    @Transactional(readOnly = true)
    public void validateCreateFileTarget(UUID userId, UUID parentId, String name) {
        ensureParentFolder(userId, parentId);
        ensureNameAvailable(userId, parentId, name);
    }

    @Transactional
    public FileNodeVM createFolder(CreateFolderCmd cmd) {
        ensureParentFolder(cmd.userId(), cmd.parentId());
        ensureNameAvailable(cmd.userId(), cmd.parentId(), cmd.name());
        return toVm(fileNodeRepository.save(FileNodeEntity.folder(cmd.userId(), cmd.parentId(), cmd.name())));
    }

    @Transactional
    public FileNodeVM createFile(CreateFileNodeCmd cmd) {
        ensureParentFolder(cmd.userId(), cmd.parentId());
        ensureNameAvailable(cmd.userId(), cmd.parentId(), cmd.name());
        var file = FileNodeEntity.file(
                cmd.userId(),
                cmd.parentId(),
                cmd.storageObjectId(),
                cmd.name(),
                cmd.sizeBytes(),
                cmd.mimeType(),
                cmd.sha256()
        );
        return toVm(fileNodeRepository.save(file));
    }

    @Transactional
    public FileNodeVM rename(UUID userId, UUID fileId, String name) {
        var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
        var normalizedName = name == null ? "" : name.trim();
        if (node.getName().equalsIgnoreCase(normalizedName)) {
            node.rename(name);
            return toVm(node);
        }
        ensureRenameNameAvailable(userId, node, normalizedName);
        node.rename(normalizedName);
        return toVm(node);
    }

    @Transactional
    public FileNodeVM move(UUID userId, UUID fileId, UUID parentId) {
        var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
        ensureParentFolder(userId, parentId);
        if ((node.getParentId() == null && parentId == null)
                || (node.getParentId() != null && node.getParentId().equals(parentId))) {
            return toVm(node);
        }
        ensureNotDescendantTarget(userId, node, parentId);
        ensureNameAvailable(userId, parentId, node.getName());
        node.moveTo(parentId);
        return toVm(node);
    }

    @Transactional
    public BatchFileActionResponse moveBatch(UUID userId, List<UUID> fileIds, UUID parentId) {
        validateBatchFileIds(fileIds);
        ensureParentFolder(userId, parentId);
        var items = new ArrayList<BatchFileActionItemVM>();
        for (var fileId : fileIds) {
            try {
                var moved = moveSingleWithoutParentValidation(userId, fileId, parentId);
                items.add(BatchFileActionItemVM.success(fileId, moved.name(), moved));
            } catch (BusinessException exception) {
                items.add(failedBatchItem(userId, fileId, exception));
            }
        }
        return BatchFileActionResponse.from(items);
    }

    @Transactional
    public FileNodeVM copy(UUID userId, UUID fileId, UUID parentId) {
        var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
        ensureParentFolder(userId, parentId);
        ensureNotDescendantTarget(userId, node, parentId);
        ensureNameAvailable(userId, parentId, node.getName());
        return toVm(copyRecursive(userId, node, parentId));
    }

    @Transactional
    public BatchFileActionResponse copyBatch(UUID userId, List<UUID> fileIds, UUID parentId) {
        validateBatchFileIds(fileIds);
        ensureParentFolder(userId, parentId);
        var items = new ArrayList<BatchFileActionItemVM>();
        for (var fileId : fileIds) {
            try {
                var copied = copySingleWithoutParentValidation(userId, fileId, parentId);
                items.add(BatchFileActionItemVM.success(fileId, copied.name(), copied));
            } catch (BusinessException exception) {
                items.add(failedBatchItem(userId, fileId, exception));
            }
        }
        return BatchFileActionResponse.from(items);
    }

    @Transactional
    public void recycle(UUID userId, UUID fileId) {
        var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
        recycleRecursive(userId, node, Instant.now());
    }

    @Transactional
    public BatchFileActionResponse recycleBatch(UUID userId, List<UUID> fileIds) {
        validateBatchFileIds(fileIds);
        var now = Instant.now();
        var items = new ArrayList<BatchFileActionItemVM>();
        for (var fileId : fileIds) {
            try {
                var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
                recycleRecursive(userId, node, now);
                items.add(BatchFileActionItemVM.success(fileId, node.getName(), toVm(node)));
            } catch (BusinessException exception) {
                items.add(failedBatchItem(userId, fileId, exception));
            }
        }
        return BatchFileActionResponse.from(items);
    }

    @Transactional(readOnly = true)
    public FileNodeEntity getActiveFileEntity(UUID userId, UUID fileId) {
        var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
        if (node.getStatus() != FileNodeStatus.ACTIVE) {
            throw new BusinessException("not_found", "File is not active", HttpStatus.NOT_FOUND);
        }
        return node;
    }

    @Transactional(readOnly = true)
    public List<FileNodeEntity> activeChildren(UUID userId, UUID parentId) {
        return fileNodeRepository.findByUserIdAndParentIdAndStatus(userId, parentId, FileNodeStatus.ACTIVE)
                .stream()
                .sorted(fileNodeComparator())
                .toList();
    }

    public static void validateBatchFileIds(List<UUID> fileIds) {
        if (fileIds == null || fileIds.isEmpty()) {
            throw new BusinessException("validation_error", "At least one file id is required", HttpStatus.BAD_REQUEST);
        }
        if (fileIds.size() > MAX_BATCH_ITEMS) {
            throw new BusinessException("validation_error", "A maximum of 10 items can be transferred at once", HttpStatus.BAD_REQUEST);
        }
        if (fileIds.stream().anyMatch(id -> id == null)) {
            throw new BusinessException("validation_error", "File id cannot be null", HttpStatus.BAD_REQUEST);
        }
        if (new HashSet<>(fileIds).size() != fileIds.size()) {
            throw new BusinessException("validation_error", "Duplicate file ids are not allowed", HttpStatus.BAD_REQUEST);
        }
    }

    public FileNodeVM toVm(FileNodeEntity node) {
        var sizeBytes = node.getType() == FileNodeType.FOLDER
                ? calculateFolderSize(node.getUserId(), node.getId(), node.getStatus(), node.getRecycledAt())
                : node.getSizeBytes();
        return new FileNodeVM(
                node.getId(),
                node.getParentId(),
                node.getName(),
                node.getType().name().toLowerCase(),
                node.getStatus().name().toLowerCase(),
                sizeBytes,
                node.getMimeType(),
                node.getSha256(),
                node.getCreatedAt(),
                node.getUpdatedAt(),
                node.getRecycledAt()
        );
    }

    private long calculateFolderSize(UUID userId, UUID folderId, FileNodeStatus status, Instant recycledAt) {
        return fileNodeRepository.findByUserIdAndParentIdAndStatus(userId, folderId, status)
                .stream()
                .filter(child -> status != FileNodeStatus.RECYCLED || Objects.equals(child.getRecycledAt(), recycledAt))
                .mapToLong(child -> child.getType() == FileNodeType.FOLDER
                        ? calculateFolderSize(userId, child.getId(), status, recycledAt)
                        : child.getSizeBytes())
                .sum();
    }

    private void recycleRecursive(UUID userId, FileNodeEntity node, Instant now) {
        node.recycle(now);
        if (node.getType() == FileNodeType.FOLDER) {
            fileNodeRepository.findByUserIdAndParentIdAndStatus(userId, node.getId(), FileNodeStatus.ACTIVE)
                    .forEach(child -> recycleRecursive(userId, child, now));
        }
    }

    private FileNodeVM moveSingleWithoutParentValidation(UUID userId, UUID fileId, UUID parentId) {
        var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
        if ((node.getParentId() == null && parentId == null)
                || (node.getParentId() != null && node.getParentId().equals(parentId))) {
            return toVm(node);
        }
        ensureNotDescendantTarget(userId, node, parentId);
        ensureNameAvailable(userId, parentId, node.getName());
        node.moveTo(parentId);
        return toVm(node);
    }

    private FileNodeVM copySingleWithoutParentValidation(UUID userId, UUID fileId, UUID parentId) {
        var node = fileNodeRepository.getByIdAndUserId(fileId, userId);
        ensureNotDescendantTarget(userId, node, parentId);
        ensureNameAvailable(userId, parentId, node.getName());
        return toVm(copyRecursive(userId, node, parentId));
    }

    private BatchFileActionItemVM failedBatchItem(UUID userId, UUID fileId, BusinessException exception) {
        var name = fileNodeRepository.findByIdAndUserId(fileId, userId)
                .map(FileNodeEntity::getName)
                .orElse(null);
        return BatchFileActionItemVM.failed(fileId, name, exception.getCode(), exception.getMessage());
    }

    private FileNodeEntity copyRecursive(UUID userId, FileNodeEntity source, UUID parentId) {
        if (source.getType() == FileNodeType.FOLDER) {
            var folderCopy = fileNodeRepository.save(FileNodeEntity.folder(userId, parentId, source.getName()));
            fileNodeRepository.findByUserIdAndParentIdAndStatus(userId, source.getId(), FileNodeStatus.ACTIVE)
                    .forEach(child -> copyRecursive(userId, child, folderCopy.getId()));
            return folderCopy;
        }

        var objectId = source.getStorageObjectId();
        if (objectId != null) {
            storageObjectService.increaseRefCount(objectId);
        }
        var fileCopy = FileNodeEntity.file(
                userId,
                parentId,
                objectId,
                source.getName(),
                source.getSizeBytes(),
                source.getMimeType(),
                source.getSha256()
        );
        return fileNodeRepository.save(fileCopy);
    }

    private void ensureNotDescendantTarget(UUID userId, FileNodeEntity node, UUID parentId) {
        if (node.getType() != FileNodeType.FOLDER || parentId == null) {
            return;
        }
        var current = fileNodeRepository.getByIdAndUserId(parentId, userId);
        if (current.getId().equals(node.getId())) {
            throw new BusinessException("validation_error", "Cannot move or copy a folder into itself", HttpStatus.BAD_REQUEST);
        }
        while (current.getParentId() != null) {
            if (current.getParentId().equals(node.getId())) {
                throw new BusinessException("validation_error", "Cannot move or copy a folder into its own child folder", HttpStatus.BAD_REQUEST);
            }
            current = fileNodeRepository.getByIdAndUserId(current.getParentId(), userId);
        }
    }

    private void ensureParentFolder(UUID userId, UUID parentId) {
        if (parentId == null) {
            return;
        }
        var parent = fileNodeRepository.getByIdAndUserId(parentId, userId);
        if (parent.getStatus() != FileNodeStatus.ACTIVE || parent.getType() != FileNodeType.FOLDER) {
            throw new BusinessException("validation_error", "Parent folder is invalid", HttpStatus.BAD_REQUEST);
        }
    }

    private void ensureNameAvailable(UUID userId, UUID parentId, String name) {
        boolean exists = parentId == null
                ? fileNodeRepository.existsByUserIdAndParentIdIsNullAndStatusAndNameIgnoreCase(userId, FileNodeStatus.ACTIVE, name)
                : fileNodeRepository.existsByUserIdAndParentIdAndStatusAndNameIgnoreCase(userId, parentId, FileNodeStatus.ACTIVE, name);
        if (exists) {
            throw new BusinessException("name_conflict", "A file with the same name already exists", HttpStatus.CONFLICT);
        }
    }

    private void ensureRenameNameAvailable(UUID userId, FileNodeEntity node, String name) {
        var siblings = node.getParentId() == null
                ? fileNodeRepository.findByUserIdAndParentIdIsNullAndStatus(userId, FileNodeStatus.ACTIVE)
                : fileNodeRepository.findByUserIdAndParentIdAndStatus(userId, node.getParentId(), FileNodeStatus.ACTIVE);
        boolean exists = siblings.stream()
                .filter(sibling -> !sibling.getId().equals(node.getId()))
                .filter(sibling -> participatesInRenameConflict(node, sibling))
                .anyMatch(sibling -> sibling.getName().equalsIgnoreCase(name));
        if (exists) {
            throw new BusinessException("name_conflict", "A file with the same name already exists", HttpStatus.CONFLICT);
        }
    }

    private boolean participatesInRenameConflict(FileNodeEntity node, FileNodeEntity sibling) {
        if (node.getParentId() == null && node.getType() == FileNodeType.FILE) {
            return sibling.getType() == FileNodeType.FILE;
        }
        return true;
    }

    private PageRequest pageRequest(int page, int perPage) {
        var safePage = Math.max(page, 1) - 1;
        var safeSize = Math.max(1, Math.min(perPage, 100));
        return PageRequest.of(safePage, safeSize, Sort.by(Sort.Order.asc("type"), Sort.Order.asc("name")));
    }

    private SearchScope parseSearchScope(String scope) {
        if (scope == null || scope.isBlank()) {
            return SearchScope.FILES;
        }
        var normalized = scope.trim().toLowerCase();
        if (normalized.equals("all")) {
            return SearchScope.ALL;
        }
        if (normalized.equals("folders") || normalized.equals("folder")) {
            return SearchScope.FOLDERS;
        }
        if (normalized.equals("files") || normalized.equals("file")) {
            return SearchScope.FILES;
        }
        throw new BusinessException("validation_error", "Search scope is invalid", HttpStatus.BAD_REQUEST);
    }

    private boolean matchesSearchScope(UUID userId, FileNodeEntity node, SearchScope searchScope, UUID parentId) {
        if (parentId != null) {
            if (searchScope == SearchScope.FILES) {
                return node.getType() == FileNodeType.FILE && isDescendantOf(userId, node, parentId);
            }
            return isDescendantOf(userId, node, parentId);
        }
        if (searchScope == SearchScope.ALL) {
            return true;
        }
        if (searchScope == SearchScope.FOLDERS) {
            return node.getType() == FileNodeType.FOLDER || node.getParentId() != null;
        }
        return node.getType() == FileNodeType.FILE && node.getParentId() == null;
    }

    private boolean isDescendantOf(UUID userId, FileNodeEntity node, UUID folderId) {
        var currentParentId = node.getParentId();
        while (currentParentId != null) {
            if (currentParentId.equals(folderId)) {
                return true;
            }
            currentParentId = fileNodeRepository.getByIdAndUserId(currentParentId, userId).getParentId();
        }
        return false;
    }

    private Comparator<FileNodeEntity> fileNodeComparator() {
        return Comparator
                .comparing((FileNodeEntity node) -> node.getType().name())
                .thenComparing(FileNodeEntity::getName, String.CASE_INSENSITIVE_ORDER);
    }

    private Page<FileNodeEntity> pageFromList(List<FileNodeEntity> nodes, int page, int perPage) {
        var safePage = Math.max(page, 1);
        var safeSize = Math.max(1, Math.min(perPage, 100));
        var fromIndex = Math.min((safePage - 1) * safeSize, nodes.size());
        var toIndex = Math.min(fromIndex + safeSize, nodes.size());
        var pageable = PageRequest.of(safePage - 1, safeSize, Sort.by(Sort.Order.asc("type"), Sort.Order.asc("name")));
        return new PageImpl<>(nodes.subList(fromIndex, toIndex), pageable, nodes.size());
    }

    private enum SearchScope {
        ALL,
        FILES,
        FOLDERS
    }
}
