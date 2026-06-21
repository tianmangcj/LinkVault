package com.linkvault.modules.uploads.dto;

import java.io.InputStream;
import java.util.UUID;

public record DirectUploadChunkCmd(
        UUID userId,
        UUID uploadId,
        long offset,
        boolean complete,
        InputStream content
) {
}
