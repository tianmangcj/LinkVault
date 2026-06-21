package com.linkvault.modules.transfers.dto;

import com.linkvault.modules.transfers.domain.TransferDirection;
import com.linkvault.modules.transfers.domain.TransferTaskStatus;
import java.util.UUID;

public record ListTransferTasksQuery(
        UUID userId,
        UUID deviceId,
        TransferDirection direction,
        TransferTaskStatus status,
        int page,
        int perPage
) {
}
