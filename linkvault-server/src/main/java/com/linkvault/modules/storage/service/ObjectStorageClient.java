package com.linkvault.modules.storage.service;

import com.linkvault.modules.storage.dto.PresignedUrlResult;
import java.time.Duration;

public interface ObjectStorageClient {

    PresignedUrlResult presignPut(String objectKey, String mimeType, Duration ttl);

    PresignedUrlResult presignGet(String objectKey, Duration ttl);
}
