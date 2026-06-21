package com.linkvault.modules.uploads.dto;

import java.util.UUID;

public record FolderUploadInitResponse(
        UUID folderUploadId,
        FolderUploadStatusVM task
) {
}
