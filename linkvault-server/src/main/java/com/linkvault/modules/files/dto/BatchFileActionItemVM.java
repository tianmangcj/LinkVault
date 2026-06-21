package com.linkvault.modules.files.dto;

import java.util.UUID;

public record BatchFileActionItemVM(
        UUID fileId,
        String name,
        boolean success,
        FileNodeVM node,
        String errorCode,
        String errorMessage
) {

    public static BatchFileActionItemVM success(UUID fileId, String name, FileNodeVM node) {
        return new BatchFileActionItemVM(fileId, name, true, node, null, null);
    }

    public static BatchFileActionItemVM failed(UUID fileId, String name, String errorCode, String errorMessage) {
        return new BatchFileActionItemVM(fileId, name, false, null, errorCode, errorMessage);
    }
}
