package com.linkvault.modules.quota.dto;

public record QuotaVM(
        long totalBytes,
        long usedBytes,
        long availableBytes,
        double usageRatio
) {
}
