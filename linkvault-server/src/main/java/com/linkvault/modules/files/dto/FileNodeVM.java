package com.linkvault.modules.files.dto;

import java.time.Instant;
import java.util.UUID;

public record FileNodeVM(
        UUID id,
        UUID parentId,
        String name,
        String type,
        String status,
        long sizeBytes,
        String mimeType,
        String sha256,
        Instant createdAt,
        Instant updatedAt,
        Instant recycledAt
) {
}
