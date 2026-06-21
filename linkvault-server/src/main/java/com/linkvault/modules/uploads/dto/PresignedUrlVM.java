package com.linkvault.modules.uploads.dto;

import java.time.Instant;
import java.util.Map;

public record PresignedUrlVM(
        String url,
        Instant expiresAt,
        Map<String, String> headers
) {
}
