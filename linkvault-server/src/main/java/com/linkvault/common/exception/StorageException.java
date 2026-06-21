package com.linkvault.common.exception;

import org.springframework.http.HttpStatus;

public class StorageException extends BusinessException {

    public StorageException(String message, Throwable cause) {
        super("object_storage_error", message, HttpStatus.BAD_GATEWAY);
        initCause(cause);
    }
}
