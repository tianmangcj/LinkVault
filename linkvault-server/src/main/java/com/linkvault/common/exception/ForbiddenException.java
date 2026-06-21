package com.linkvault.common.exception;

import org.springframework.http.HttpStatus;

public class ForbiddenException extends BusinessException {

    public ForbiddenException(String message) {
        super("forbidden", message, HttpStatus.FORBIDDEN);
    }
}
