package com.linkvault.modules.uploads.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.PositiveOrZero;

public record DirectUploadInitRequest(
        @NotBlank String fileName,
        @PositiveOrZero long sizeBytes,
        String mimeType
) {
}
