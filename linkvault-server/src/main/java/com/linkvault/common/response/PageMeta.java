package com.linkvault.common.response;

public record PageMeta(
        int page,
        int perPage,
        long total,
        int totalPages
) {
}
