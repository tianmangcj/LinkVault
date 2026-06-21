package com.linkvault.modules.transfers.domain;

public enum TransferTaskStatus {
    WAITING,
    ACTIVE,
    PAUSED,
    DONE,
    FAILED,
    CANCELED;

    public static TransferTaskStatus from(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return TransferTaskStatus.valueOf(value.trim().toUpperCase());
    }
}
