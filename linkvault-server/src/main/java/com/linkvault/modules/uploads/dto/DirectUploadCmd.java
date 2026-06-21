package com.linkvault.modules.uploads.dto;

import java.io.InputStream;
import java.util.UUID;

public record DirectUploadCmd(
        UUID userId,
        UUID uploadId,
        UUID parentId,
        String fileName,
        long sizeBytes,
        String mimeType,
        InputStream content
) {
}
