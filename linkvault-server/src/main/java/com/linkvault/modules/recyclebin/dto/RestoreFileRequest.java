package com.linkvault.modules.recyclebin.dto;

import java.util.UUID;

public record RestoreFileRequest(
        Boolean useOriginalPath,
        UUID parentId
) {
}
