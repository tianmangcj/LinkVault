package com.linkvault.modules.downloads.dto;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

public record PrepareDownloadResponse(
        UUID downloadTaskId,
        UUID fileId,
        String fileName,
        long sizeBytes,
        String mimeType,
        String url,
        Instant expiresAt,
        Map<String, String> headers
) {
}
