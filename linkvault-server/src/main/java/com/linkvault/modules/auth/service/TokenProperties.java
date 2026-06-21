package com.linkvault.modules.auth.service;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "linkvault.security")
public record TokenProperties(
        String jwtSecret,
        Duration accessTokenTtl,
        Duration refreshTokenTtl
) {
}
