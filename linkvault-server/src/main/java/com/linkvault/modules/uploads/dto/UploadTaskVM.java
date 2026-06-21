package com.linkvault.modules.uploads.dto;

import java.time.Instant;
import java.util.UUID;

public record UploadTaskVM(
        UUID id,
        String fileName,
        long sizeBytes,
        long transferredBytes,
        String status,
        Instant createdAt,
        Instant updatedAt,
        Instant completedAt
) {
}
