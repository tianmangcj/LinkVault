package com.linkvault.modules.storage.domain;

import com.linkvault.common.domain.BaseEntity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Table;
import java.time.Instant;

@Entity
@Table(name = "storage_objects")
public class StorageObjectEntity extends BaseEntity {

    @Column(name = "bucket", nullable = false, length = 120)
    private String bucket;

    @Column(name = "object_key", nullable = false, unique = true, length = 420)
    private String objectKey;

    @Column(name = "sha256", nullable = false, length = 64)
    private String sha256;

    @Column(name = "size_bytes", nullable = false)
    private long sizeBytes;

    @Column(name = "mime_type", length = 160)
    private String mimeType;

    @Column(name = "reference_count", nullable = false)
    private long referenceCount;

    @Column(name = "pending_delete_at")
    private Instant pendingDeleteAt;

    protected StorageObjectEntity() {
    }

    private StorageObjectEntity(String bucket, String objectKey, String sha256, long sizeBytes, String mimeType) {
        this.bucket = bucket;
        this.objectKey = objectKey;
        this.sha256 = sha256;
        this.sizeBytes = sizeBytes;
        this.mimeType = mimeType;
        this.referenceCount = 1;
    }

    public static StorageObjectEntity create(
            String bucket,
            String objectKey,
            String sha256,
            long sizeBytes,
            String mimeType
    ) {
        return new StorageObjectEntity(bucket, objectKey, sha256, sizeBytes, mimeType);
    }

    public void increaseRefCount() {
        referenceCount += 1;
        pendingDeleteAt = null;
    }

    public void releaseReference(Instant now) {
        if (referenceCount > 0) {
            referenceCount -= 1;
        }
        if (referenceCount == 0) {
            pendingDeleteAt = now;
        }
    }

    public String getBucket() {
        return bucket;
    }

    public String getObjectKey() {
        return objectKey;
    }

    public String getSha256() {
        return sha256;
    }

    public long getSizeBytes() {
        return sizeBytes;
    }

    public String getMimeType() {
        return mimeType;
    }

    public long getReferenceCount() {
        return referenceCount;
    }
}
