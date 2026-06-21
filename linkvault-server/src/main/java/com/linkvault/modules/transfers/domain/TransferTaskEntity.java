package com.linkvault.modules.transfers.domain;

import com.linkvault.common.domain.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "transfer_tasks")
public class TransferTaskEntity extends BaseEntity {

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "device_id", nullable = false)
    private UUID deviceId;

    @Enumerated(EnumType.STRING)
    @Column(name = "direction", nullable = false, length = 24)
    private TransferDirection direction;

    @Enumerated(EnumType.STRING)
    @Column(name = "task_type", nullable = false, length = 24)
    private TransferTaskType taskType;

    @Column(name = "source_id", nullable = false)
    private UUID sourceId;

    @Column(name = "title", nullable = false, length = 255)
    private String title;

    @Column(name = "total_bytes", nullable = false)
    private long totalBytes;

    @Column(name = "transferred_bytes", nullable = false)
    private long transferredBytes;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 24)
    private TransferTaskStatus status;

    @Column(name = "failure_reason", length = 500)
    private String failureReason;

    @Column(name = "completed_at")
    private Instant completedAt;

    @Column(name = "hidden_at")
    private Instant hiddenAt;

    protected TransferTaskEntity() {
    }

    private TransferTaskEntity(
            UUID userId,
            UUID deviceId,
            TransferDirection direction,
            TransferTaskType taskType,
            UUID sourceId,
            String title,
            long totalBytes
    ) {
        this.userId = userId;
        this.deviceId = deviceId;
        this.direction = direction;
        this.taskType = taskType;
        this.sourceId = sourceId;
        this.title = title;
        this.totalBytes = totalBytes;
        this.transferredBytes = 0;
        this.status = TransferTaskStatus.ACTIVE;
    }

    public static TransferTaskEntity create(
            UUID userId,
            UUID deviceId,
            TransferDirection direction,
            TransferTaskType taskType,
            UUID sourceId,
            String title,
            long totalBytes
    ) {
        return new TransferTaskEntity(userId, deviceId, direction, taskType, sourceId, title, totalBytes);
    }

    public void updateProgress(long transferredBytes) {
        this.transferredBytes = Math.max(0, Math.min(totalBytes, transferredBytes));
        if (this.transferredBytes >= totalBytes && totalBytes > 0) {
            complete();
        }
    }

    public void pause() {
        if (status == TransferTaskStatus.ACTIVE || status == TransferTaskStatus.WAITING) {
            status = TransferTaskStatus.PAUSED;
        }
    }

    public void resume() {
        if (status == TransferTaskStatus.PAUSED) {
            status = TransferTaskStatus.ACTIVE;
        }
    }

    public void complete() {
        status = TransferTaskStatus.DONE;
        transferredBytes = totalBytes;
        completedAt = Instant.now();
    }

    public void fail(String reason) {
        status = TransferTaskStatus.FAILED;
        failureReason = reason;
        completedAt = Instant.now();
    }

    public void cancel() {
        if (status != TransferTaskStatus.DONE) {
            status = TransferTaskStatus.CANCELED;
            completedAt = Instant.now();
        }
    }

    public void hide(Instant now) {
        hiddenAt = now;
    }

    public UUID getUserId() {
        return userId;
    }

    public UUID getDeviceId() {
        return deviceId;
    }

    public TransferDirection getDirection() {
        return direction;
    }

    public TransferTaskType getTaskType() {
        return taskType;
    }

    public UUID getSourceId() {
        return sourceId;
    }

    public String getTitle() {
        return title;
    }

    public long getTotalBytes() {
        return totalBytes;
    }

    public long getTransferredBytes() {
        return transferredBytes;
    }

    public TransferTaskStatus getStatus() {
        return status;
    }

    public String getFailureReason() {
        return failureReason;
    }

    public Instant getCompletedAt() {
        return completedAt;
    }
}
