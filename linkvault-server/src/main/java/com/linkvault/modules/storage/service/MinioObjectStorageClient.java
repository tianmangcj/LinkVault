package com.linkvault.modules.storage.service;

import com.linkvault.common.exception.StorageException;
import com.linkvault.modules.storage.dto.PresignedUrlResult;
import io.minio.GetPresignedObjectUrlArgs;
import io.minio.MinioClient;
import io.minio.http.Method;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import org.springframework.stereotype.Component;

@Component
public class MinioObjectStorageClient implements ObjectStorageClient {
    private final MinioClient minioClient;
    private final StorageProperties properties;

    public MinioObjectStorageClient(MinioClient minioClient, StorageProperties properties) {
        this.minioClient = minioClient;
        this.properties = properties;
    }

    @Override
    public PresignedUrlResult presignPut(String objectKey, String mimeType, Duration ttl) {
        var headers = mimeType == null || mimeType.isBlank()
                ? Map.<String, String>of()
                : Map.of("Content-Type", mimeType);
        return new PresignedUrlResult(
                rewritePublicEndpoint(presign(Method.PUT, objectKey, ttl, headers)),
                Instant.now().plus(ttl),
                headers
        );
    }

    @Override
    public PresignedUrlResult presignGet(String objectKey, Duration ttl) {
        return new PresignedUrlResult(
                rewritePublicEndpoint(presign(Method.GET, objectKey, ttl, Map.of())),
                Instant.now().plus(ttl),
                Map.of()
        );
    }

    private String presign(Method method, String objectKey, Duration ttl, Map<String, String> headers) {
        try {
            return minioClient.getPresignedObjectUrl(GetPresignedObjectUrlArgs.builder()
                    .method(method)
                    .bucket(properties.bucket())
                    .object(objectKey)
                    .expiry(Math.toIntExact(ttl.toSeconds()))
                    .extraHeaders(headers)
                    .build());
        } catch (Exception ex) {
            throw new StorageException("Unable to create MinIO presigned URL", ex);
        }
    }

    private String rewritePublicEndpoint(String signedUrl) {
        var internal = properties.endpoint().replaceAll("/+$", "");
        var external = properties.publicEndpoint().replaceAll("/+$", "");
        if (internal.equals(external) || !signedUrl.startsWith(internal)) {
            return signedUrl;
        }
        return external + signedUrl.substring(internal.length());
    }
}
