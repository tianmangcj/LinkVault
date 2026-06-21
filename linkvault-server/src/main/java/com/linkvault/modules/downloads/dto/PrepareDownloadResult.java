package com.linkvault.modules.downloads.dto;

import com.linkvault.modules.storage.dto.PresignedUrlResult;
import java.util.UUID;

public record PrepareDownloadResult(
        UUID downloadTaskId,
        UUID fileId,
        String fileName,
        long sizeBytes,
        String mimeType,
        PresignedUrlResult presignedUrl
) {
}
