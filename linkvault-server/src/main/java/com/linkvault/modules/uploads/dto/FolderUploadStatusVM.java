package com.linkvault.modules.uploads.dto;

import java.time.Instant;
import java.util.UUID;

public record FolderUploadStatusVM(
        UUID id,
        String folderName,
        int fileCount,
        long totalBytes,
        String status,
        Instant createdAt,
        Instant updatedAt
) {
}
