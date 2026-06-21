package com.linkvault.modules.downloads.dto;

import jakarta.validation.constraints.NotNull;
import java.util.UUID;

public record PrepareDownloadRequest(
        @NotNull UUID fileId
) {
}
