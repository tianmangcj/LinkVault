package com.linkvault.modules.transfers.domain;

public enum TransferDirection {
    UPLOAD,
    DOWNLOAD;

    public static TransferDirection from(String value) {
        if (value == null || value.isBlank()) {
            return UPLOAD;
        }
        return TransferDirection.valueOf(value.trim().toUpperCase());
    }
}
