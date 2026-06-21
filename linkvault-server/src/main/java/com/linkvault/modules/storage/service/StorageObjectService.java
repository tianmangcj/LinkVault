package com.linkvault.modules.storage.service;

import com.linkvault.modules.storage.domain.StorageObjectEntity;
import com.linkvault.modules.storage.repository.StorageObjectRepository;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class StorageObjectService {
    private final StorageObjectRepository storageObjectRepository;
    private final String bucket;

    public StorageObjectService(
            StorageObjectRepository storageObjectRepository,
            @Value("${linkvault.storage.bucket:linkvault}") String bucket
    ) {
        this.storageObjectRepository = storageObjectRepository;
        this.bucket = bucket;
    }

    @Transactional(readOnly = true)
    public Optional<StorageObjectEntity> findDedupCandidate(String sha256, long sizeBytes) {
        return storageObjectRepository.findFirstBySha256AndSizeBytesAndPendingDeleteAtIsNull(sha256, sizeBytes);
    }

    @Transactional
    public StorageObjectEntity createObject(String objectKey, String sha256, long sizeBytes, String mimeType) {
        return storageObjectRepository.save(StorageObjectEntity.create(bucket, objectKey, sha256, sizeBytes, mimeType));
    }

    @Transactional
    public StorageObjectEntity increaseRefCount(UUID objectId) {
        var object = storageObjectRepository.getByIdOrThrow(objectId);
        object.increaseRefCount();
        return object;
    }

    @Transactional
    public void releaseReference(UUID objectId) {
        var object = storageObjectRepository.getByIdOrThrow(objectId);
        object.releaseReference(Instant.now());
    }

    @Transactional(readOnly = true)
    public StorageObjectEntity get(UUID objectId) {
        return storageObjectRepository.getByIdOrThrow(objectId);
    }
}
