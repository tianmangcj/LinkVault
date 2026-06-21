package com.linkvault.modules.quota.domain;

import com.linkvault.common.domain.BaseEntity;
import com.linkvault.common.exception.BusinessException;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import java.util.UUID;
import org.springframework.http.HttpStatus;

@Entity
@Table(name = "user_quotas")
public class UserQuotaEntity extends BaseEntity {
    public static final long DEFAULT_TOTAL_BYTES = 10L * 1024L * 1024L * 1024L;

    @Column(name = "user_id", nullable = false, unique = true)
    private UUID userId;

    @Column(name = "total_bytes", nullable = false)
    private long totalBytes;

    @Column(name = "used_bytes", nullable = false)
    private long usedBytes;

    protected UserQuotaEntity() {
    }

    private UserQuotaEntity(UUID userId, long totalBytes) {
        this.userId = userId;
        this.totalBytes = totalBytes;
        this.usedBytes = 0;
    }

    public static UserQuotaEntity createDefault(UUID userId) {
        return new UserQuotaEntity(userId, DEFAULT_TOTAL_BYTES);
    }

    public void commitUpload(long bytes) {
        if (bytes < 0) {
            throw new IllegalArgumentException("bytes must be positive");
        }
        if (usedBytes + bytes > totalBytes) {
            throw new BusinessException("quota_exceeded", "Storage quota exceeded", HttpStatus.UNPROCESSABLE_ENTITY);
        }
        usedBytes += bytes;
    }

    public void releaseUsedBytes(long bytes) {
        if (bytes <= 0) {
            return;
        }
        usedBytes = Math.max(0, usedBytes - bytes);
    }

    public UUID getUserId() {
        return userId;
    }

    public long getTotalBytes() {
        return totalBytes;
    }

    public long getUsedBytes() {
        return usedBytes;
    }

    public long getAvailableBytes() {
        return Math.max(0, totalBytes - usedBytes);
    }
}
