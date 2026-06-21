package com.linkvault.modules.transfers.dto;

import java.util.UUID;

public record UpdateTransferProgressCmd(
        UUID userId,
        UUID deviceId,
        UUID taskId,
        long transferredBytes
) {
}
