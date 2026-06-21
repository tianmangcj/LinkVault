package com.linkvault.modules.transfers.dto;

import com.linkvault.modules.transfers.domain.TransferDirection;
import com.linkvault.modules.transfers.domain.TransferTaskType;
import java.util.UUID;

public record CreateTransferTaskCmd(
        UUID userId,
        UUID deviceId,
        TransferDirection direction,
        TransferTaskType taskType,
        UUID sourceId,
        String title,
        long totalBytes
) {
}
