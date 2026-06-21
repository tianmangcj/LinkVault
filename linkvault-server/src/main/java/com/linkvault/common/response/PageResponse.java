package com.linkvault.common.response;

import java.util.List;
import java.util.function.Function;
import org.springframework.data.domain.Page;

public record PageResponse<T>(
        List<T> items,
        PageMeta meta
) {

    public static <T> PageResponse<T> from(Page<T> page) {
        return new PageResponse<>(
                page.getContent(),
                new PageMeta(page.getNumber() + 1, page.getSize(), page.getTotalElements(), page.getTotalPages())
        );
    }

    public static <T, R> PageResponse<R> from(Page<T> page, Function<T, R> mapper) {
        return new PageResponse<>(
                page.getContent().stream().map(mapper).toList(),
                new PageMeta(page.getNumber() + 1, page.getSize(), page.getTotalElements(), page.getTotalPages())
        );
    }
}
