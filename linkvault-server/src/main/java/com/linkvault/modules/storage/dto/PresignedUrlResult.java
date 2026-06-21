package com.linkvault.modules.storage.dto;

import java.time.Instant;
import java.util.Map;

public record PresignedUrlResult(
        String url,
        Instant expiresAt,
        Map<String, String> headers
) {
}
