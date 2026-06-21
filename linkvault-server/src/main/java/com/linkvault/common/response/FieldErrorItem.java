package com.linkvault.common.response;

public record FieldErrorItem(
        String field,
        String message,
        String code
) {
}
