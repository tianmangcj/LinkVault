package com.linkvault.modules.files.dto;

import com.linkvault.modules.files.domain.FileNodeType;
import java.util.UUID;

public record ListFilesQuery(
        UUID userId,
        UUID parentId,
        FileNodeType type,
        int page,
        int perPage
) {
}
