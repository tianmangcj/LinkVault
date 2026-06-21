package com.linkvault.modules.uploads.domain;

import com.linkvault.common.domain.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "upload_tasks")
public class UploadTaskEntity extends BaseEntity {

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "parent_id")
    private UUID parentId;

    @Column(name = "file_name", nullable = false, length = 255)
    private String fileName;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(name = "mime_type", length = 160)
    private String mimeType;

    @Column(name = "sha256", nullable = false, length = 64)
    private String sha256;

    @Column(name = "object_key", nullable = false, length = 420)
    private String objectKey;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private UploadTaskStatus status;

    @Column(name = "transferred_bytes", nullable = false)
    private long transferredBytes;

    @Column(name = "completed_at")
    private Instant completedAt;

    protected UploadTaskEntity() {
    }

    private UploadTaskEntity(UUID userId, UUID parentId, String fileName, long sizeBytes, String mimeType, String sha256, String objectKey) {
        this.userId = userId;
        this.parentId = parentId;
        this.fileName = fileName;
        this.sizeBytes = sizeBytes;
        this.mimeType = mimeType;
        this.sha256 = sha256;
        this.objectKey = objectKey;
        this.status = UploadTaskStatus.ACTIVE;
        this.transferredBytes = 0;
    }

    public static UploadTaskEntity create(UUID userId, UUID parentId, String fileName, long sizeBytes, String mimeType, String sha256, String objectKey) {
        return new UploadTaskEntity(userId, parentId, fileName, sizeBytes, mimeType, sha256, objectKey);
    }

    public void complete(Instant now) {
        status = UploadTaskStatus.DONE;
        transferredBytes = sizeBytes;
        completedAt = now;
    }

    public void reportProgress(long transferredBytes) {
        this.transferredBytes = Math.max(0, Math.min(sizeBytes, transferredBytes));
        if (this.transferredBytes > 0 && (status == UploadTaskStatus.WAITING || status == UploadTaskStatus.PAUSED)) {
            status = UploadTaskStatus.ACTIVE;
        }
    }

    public void resetProgress() {
        transferredBytes = 0;
        if (status == UploadTaskStatus.PAUSED || status == UploadTaskStatus.FAILED) {
            status = UploadTaskStatus.ACTIVE;
        }
    }

    public void markStored(String sha256, String mimeType) {
        this.sha256 = sha256;
        if (mimeType != null && !mimeType.isBlank()) {
            this.mimeType = mimeType;
        }
    }

    public void fail() {
        if (status != UploadTaskStatus.DONE && status != UploadTaskStatus.CANCELED) {
            status = UploadTaskStatus.FAILED;
        }
    }

    public void pause() {
        if (status == UploadTaskStatus.ACTIVE || status == UploadTaskStatus.WAITING) {
            status = UploadTaskStatus.PAUSED;
        }
    }

    public void resume() {
        if (status == UploadTaskStatus.PAUSED) {
            status = UploadTaskStatus.ACTIVE;
        }
    }

    public void cancel() {
        if (status != UploadTaskStatus.DONE) {
            status = UploadTaskStatus.CANCELED;
        }
    }

    public UUID getUserId() {
        return userId;
    }

    public UUID getParentId() {
        return parentId;
    }

    public String getFileName() {
        return fileName;
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

    public String getObjectKey() {
        return objectKey;
    }

    public UploadTaskStatus getStatus() {
        return status;
    }

    public long getTransferredBytes() {
        return transferredBytes;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }
}
