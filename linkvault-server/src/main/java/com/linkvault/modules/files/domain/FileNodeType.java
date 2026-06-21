package com.linkvault.modules.files.domain;

public enum FileNodeType {
    FILE,
    FOLDER;

    public static FileNodeType from(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return FileNodeType.valueOf(value.trim().toUpperCase());
    }
}
