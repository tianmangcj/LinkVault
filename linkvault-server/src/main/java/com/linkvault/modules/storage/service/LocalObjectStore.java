package com.linkvault.modules.storage.service;

import com.linkvault.common.exception.StorageException;
import io.minio.GetObjectArgs;
import io.minio.MinioClient;
import io.minio.PutObjectArgs;
import io.minio.RemoveObjectArgs;
import java.io.IOException;
import java.io.InputStream;
import org.springframework.stereotype.Component;

@Component
public class LocalObjectStore {
    private static final long UNKNOWN_OBJECT_SIZE = -1;
    private static final long MINIO_PART_SIZE = 10L * 1024L * 1024L;
    private final MinioClient minioClient;
    private final StorageProperties properties;

    public LocalObjectStore(MinioClient minioClient, StorageProperties properties) {
        this.minioClient = minioClient;
        this.properties = properties;
    }

    public void save(String objectKey, InputStream inputStream) throws IOException {
        save(objectKey, inputStream, UNKNOWN_OBJECT_SIZE, null);
    }

    public void save(String objectKey, InputStream inputStream, long sizeBytes, String contentType) throws IOException {
        try {
            var builder = PutObjectArgs.builder()
                    .bucket(properties.bucket())
                    .object(objectKey)
                    .stream(inputStream, sizeBytes, MINIO_PART_SIZE);
            if (contentType != null && !contentType.isBlank()) {
                builder.contentType(contentType);
            }
            minioClient.putObject(builder.build());
        } catch (Exception ex) {
            throw new IOException("Unable to store MinIO object", ex);
        }
    }

    public InputStream open(String objectKey) throws IOException {
        try {
            return minioClient.getObject(GetObjectArgs.builder()
                    .bucket(properties.bucket())
                    .object(objectKey)
                    .build());
        } catch (Exception ex) {
            throw new StorageException("Unable to open MinIO object", ex);
        }
    }

    public void deleteIfExists(String objectKey) {
        try {
            minioClient.removeObject(RemoveObjectArgs.builder()
                    .bucket(properties.bucket())
                    .object(objectKey)
                    .build());
        } catch (Exception ex) {
            throw new StorageException("Unable to delete MinIO object", ex);
        }
    }
}
