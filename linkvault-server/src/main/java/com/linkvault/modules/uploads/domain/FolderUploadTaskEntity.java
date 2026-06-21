package com.linkvault.modules.uploads.domain;

import com.linkvault.common.domain.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import java.util.UUID;

@Entity
@Table(name = "folder_upload_tasks")
public class FolderUploadTaskEntity extends BaseEntity {

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "parent_id")
    private UUID parentId;

    @Column(name = "folder_name", nullable = false, length = 255)
    private String folderName;

    @Column(name = "file_count", nullable = false)
    private int fileCount;

    @Column(name = "total_bytes", nullable = false)
    private long totalBytes;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private UploadTaskStatus status;

    protected FolderUploadTaskEntity() {
    }

    private FolderUploadTaskEntity(UUID userId, UUID parentId, String folderName, int fileCount, long totalBytes) {
        this.userId = userId;
        this.parentId = parentId;
        this.folderName = folderName;
        this.fileCount = fileCount;
        this.totalBytes = totalBytes;
        this.status = UploadTaskStatus.ACTIVE;
    }

    public static FolderUploadTaskEntity create(UUID userId, UUID parentId, String folderName, int fileCount, long totalBytes) {
        return new FolderUploadTaskEntity(userId, parentId, folderName, fileCount, totalBytes);
    }

    public void pause() {
        status = UploadTaskStatus.PAUSED;
    }

    public void resume() {
        status = UploadTaskStatus.ACTIVE;
    }

    public void cancel() {
        status = UploadTaskStatus.CANCELED;
    }

    public UUID getUserId() {
        return userId;
    }

    public UUID getParentId() {
        return parentId;
    }

    public String getFolderName() {
        return folderName;
    }

    public int getFileCount() {
        return fileCount;
    }

    public long getTotalBytes() {
        return totalBytes;
    }

    public UploadTaskStatus getStatus() {
        return status;
    }
}
