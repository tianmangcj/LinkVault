package com.linkvault.modules.files.dto;

import java.util.UUID;

public record CreateFolderCmd(
        UUID userId,
        UUID parentId,
        String name
) {
}
