package com.linkvault.modules.uploads.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.PositiveOrZero;
import java.util.UUID;

public record FolderUploadInitRequest(
        UUID parentId,
        @NotBlank String folderName,
        @PositiveOrZero int fileCount,
        @PositiveOrZero long totalBytes
) {
}
