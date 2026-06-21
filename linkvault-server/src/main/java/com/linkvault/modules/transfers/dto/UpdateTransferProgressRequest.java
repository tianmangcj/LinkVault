package com.linkvault.modules.transfers.dto;

import jakarta.validation.constraints.PositiveOrZero;

public record UpdateTransferProgressRequest(
        @PositiveOrZero long transferredBytes
) {
}
