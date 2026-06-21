package com.linkvault.modules.uploads.dto;

import java.util.UUID;

public record InitUploadResponse(
        UUID uploadId,
        boolean instantAvailable,
        PresignedUrlVM uploadUrl,
        UploadTaskVM task
) {
}
