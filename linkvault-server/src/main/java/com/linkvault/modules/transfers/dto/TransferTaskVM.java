package com.linkvault.modules.transfers.dto;

import java.time.Instant;
import java.util.UUID;

public record TransferTaskVM(
        UUID id,
        UUID deviceId,
        String direction,
        String taskType,
        UUID sourceId,
        String title,
        long totalBytes,
        long transferredBytes,
        double progress,
        String status,
        String failureReason,
        Instant createdAt,
        Instant updatedAt,
        Instant completedAt
) {
}
