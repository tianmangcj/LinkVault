package com.linkvault.modules.health;

import java.time.Instant;
import java.util.Map;

public record HealthResponse(
        String status,
        String service,
        Instant checkedAt,
        Map<String, String> dependencies
) {
}
