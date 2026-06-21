package com.linkvault.modules.downloads.dto;

import java.util.UUID;

public record PrepareDownloadCmd(
        UUID userId,
        UUID deviceId,
        UUID fileId
) {
}
