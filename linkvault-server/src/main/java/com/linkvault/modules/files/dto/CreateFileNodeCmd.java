package com.linkvault.modules.files.dto;

import java.util.UUID;

public record CreateFileNodeCmd(
        UUID userId,
        UUID parentId,
        UUID storageObjectId,
        String name,
        long sizeBytes,
        String mimeType,
        String sha256
) {
}
