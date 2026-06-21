package com.linkvault.modules.downloads.domain;

import com.linkvault.common.domain.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "download_tasks")
public class DownloadTaskEntity extends BaseEntity {

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "file_id", nullable = false)
    private UUID fileId;

    @Column(name = "file_name", nullable = false, length = 255)
    private String fileName;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(name = "downloaded_bytes", nullable = false)
    private long downloadedBytes;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private DownloadTaskStatus status;

    @Column(name = "completed_at")
    private Instant completedAt;

    protected DownloadTaskEntity() {
    }

    private DownloadTaskEntity(UUID userId, UUID fileId, String fileName, long sizeBytes) {
        this.userId = userId;
        this.fileId = fileId;
        this.fileName = fileName;
        this.sizeBytes = sizeBytes;
        this.downloadedBytes = 0;
        this.status = DownloadTaskStatus.ACTIVE;
    }

    public static DownloadTaskEntity create(UUID userId, UUID fileId, String fileName, long sizeBytes) {
        return new DownloadTaskEntity(userId, fileId, fileName, sizeBytes);
    }

    public void reportProgress(long downloadedBytes) {
        this.downloadedBytes = Math.max(0, Math.min(sizeBytes, downloadedBytes));
        if (status == DownloadTaskStatus.PAUSED && this.downloadedBytes < sizeBytes) {
            status = DownloadTaskStatus.ACTIVE;
        }
    }

    public void complete() {
        status = DownloadTaskStatus.DONE;
        downloadedBytes = sizeBytes;
        completedAt = Instant.now();
    }

    public void pause() {
        if (status == DownloadTaskStatus.ACTIVE) {
            status = DownloadTaskStatus.PAUSED;
        }
    }

    public void resume() {
        if (status == DownloadTaskStatus.PAUSED) {
            status = DownloadTaskStatus.ACTIVE;
        }
    }

    public void cancel() {
        if (status != DownloadTaskStatus.DONE) {
            status = DownloadTaskStatus.CANCELED;
            completedAt = Instant.now();
        }
    }

    public UUID getUserId() {
        return userId;
    }

    public UUID getFileId() {
        return fileId;
    }

    public String getFileName() {
        return fileName;
    }

    public long getSizeBytes() {
        return sizeBytes;
    }

    public long getDownloadedBytes() {
        return downloadedBytes;
    }

    public DownloadTaskStatus getStatus() {
        return status;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }
}
