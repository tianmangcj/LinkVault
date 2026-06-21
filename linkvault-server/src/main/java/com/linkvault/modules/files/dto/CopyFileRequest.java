package com.linkvault.modules.files.dto;

import java.util.UUID;

public record CopyFileRequest(
        UUID parentId
) {
}
