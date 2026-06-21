package com.linkvault.common.domain;

import java.util.UUID;

public final class IdGenerator {
    private IdGenerator() {
    }

    public static UUID generate() {
        return UUID.randomUUID();
    }
}
