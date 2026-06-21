package com.linkvault.modules.downloads.dto;

import jakarta.validation.constraints.PositiveOrZero;

public record ReportDownloadProgressRequest(
        @PositiveOrZero long downloadedBytes
) {
}
