package com.linkvault.modules.files.domain;

import com.linkvault.common.domain.BaseEntity;
import com.linkvault.common.exception.BusinessException;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.springframework.http.HttpStatus;

@Entity
@Table(name = "file_nodes")
public class FileNodeEntity extends BaseEntity {

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "parent_id")
    private UUID parentId;

    @Column(name = "storage_object_id")
    private UUID storageObjectId;

    @Column(name = "name", nullable = false, length = 255)
    private String name;

    @Enumerated(EnumType.STRING)
    @Column(name = "type", nullable = false, length = 24)
    private FileNodeType type;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private FileNodeStatus status;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(name = "mime_type", length = 160)
    private String mimeType;

    @Column(name = "sha256", length = 64)
    private String sha256;

    @Column(name = "recycled_at")
    private Instant recycledAt;

    @Column(name = "purged_at")
    private Instant purgedAt;

    protected FileNodeEntity() {
    }

    private FileNodeEntity(
            UUID userId,
            UUID parentId,
            UUID storageObjectId,
            String name,
            FileNodeType type,
            long sizeBytes,
            String mimeType,
            String sha256
    ) {
        this.userId = userId;
        this.parentId = parentId;
        this.storageObjectId = storageObjectId;
        this.name = normalizeName(name);
        this.type = type;
        this.status = FileNodeStatus.ACTIVE;
        this.sizeBytes = sizeBytes;
        this.mimeType = mimeType;
        this.sha256 = sha256;
    }

    public static FileNodeEntity folder(UUID userId, UUID parentId, String name) {
        return new FileNodeEntity(userId, parentId, null, name, FileNodeType.FOLDER, 0, null, null);
    }

    public static FileNodeEntity file(
            UUID userId,
            UUID parentId,
            UUID storageObjectId,
            String name,
            long sizeBytes,
            String mimeType,
            String sha256
    ) {
        return new FileNodeEntity(userId, parentId, storageObjectId, name, FileNodeType.FILE, sizeBytes, mimeType, sha256);
    }

    public void rename(String newName) {
        this.name = normalizeName(newName);
    }

    public void moveTo(UUID newParentId) {
        if (getId().equals(newParentId)) {
            throw new BusinessException("validation_error", "Cannot move a folder into itself", HttpStatus.BAD_REQUEST);
        }
        this.parentId = newParentId;
    }

    public void recycle(Instant now) {
        if (status == FileNodeStatus.ACTIVE) {
            status = FileNodeStatus.RECYCLED;
            recycledAt = now;
        }
    }

    public void restore() {
        if (status == FileNodeStatus.RECYCLED) {
            status = FileNodeStatus.ACTIVE;
            recycledAt = null;
        }
    }

    public void purge(Instant now) {
        status = FileNodeStatus.PURGED;
        purgedAt = now;
    }

    public UUID getUserId() {
        return userId;
    }

    public UUID getParentId() {
        return parentId;
    }

    public UUID getStorageObjectId() {
        return storageObjectId;
    }

    public String getName() {
        return name;
    }

    public FileNodeType getType() {
        return type;
    }

    public FileNodeStatus getStatus() {
        return status;
    }

    public long getSizeBytes() {
        return sizeBytes;
    }

    public String getMimeType() {
        return mimeType;
    }

    public String getSha256() {
        return sha256;
    }

    public Instant getRecycledAt() {
        return recycledAt;
    }

    private static String normalizeName(String name) {
        if (name == null || name.isBlank()) {
            throw new BusinessException("validation_error", "File name is required", HttpStatus.BAD_REQUEST);
        }
        var normalized = name.trim();
        if (normalized.contains("/") || normalized.contains("\\")) {
            throw new BusinessException("validation_error", "File name cannot contain path separators", HttpStatus.BAD_REQUEST);
        }
        return normalized;
    }
}
