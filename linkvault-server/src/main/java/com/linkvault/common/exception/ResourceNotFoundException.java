package com.linkvault.common.exception;

import org.springframework.http.HttpStatus;

public class ResourceNotFoundException extends BusinessException {

    public ResourceNotFoundException(String resource, Object id) {
        super("not_found", resource + " not found: " + id, HttpStatus.NOT_FOUND);
    }
}
