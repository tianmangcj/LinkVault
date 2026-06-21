package com.linkvault.modules.uploads.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.PositiveOrZero;
import java.util.UUID;

public record InitUploadRequest(
        UUID parentId,
        @NotBlank String fileName,
        @PositiveOrZero long sizeBytes,
        String mimeType,
        @NotBlank String sha256
) {
}
