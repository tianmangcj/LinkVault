package com.linkvault.modules.uploads.dto;

import java.util.UUID;

public record InitUploadCmd(
        UUID userId,
        UUID deviceId,
        UUID parentId,
        String fileName,
        long sizeBytes,
        String mimeType,
        String sha256
) {
}
