package com.linkvault.modules.auth.service;

import com.linkvault.common.exception.UnauthorizedException;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.auth.dto.IssuedRefreshToken;
import com.linkvault.modules.auth.dto.IssuedToken;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.UUID;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Service;

@Service
@EnableConfigurationProperties(TokenProperties.class)
public class JwtTokenService {
    private static final String HMAC_ALGORITHM = "HmacSHA256";
    private final TokenProperties properties;

    public JwtTokenService(TokenProperties properties) {
        this.properties = properties;
    }

    public IssuedToken issueAccessToken(UserPrincipal principal) {
        var expiresAt = Instant.now().plus(properties.accessTokenTtl());
        var payload = String.join("|",
                principal.userId().toString(),
                principal.deviceId().toString(),
                principal.username(),
                principal.role(),
                Long.toString(expiresAt.getEpochSecond())
        );
        return new IssuedToken(encodeSigned(payload), expiresAt);
    }

    public IssuedRefreshToken issueRefreshToken(UUID userId, UUID deviceId) {
        var expiresAt = Instant.now().plus(properties.refreshTokenTtl());
        var raw = userId + "." + deviceId + "." + UUID.randomUUID() + "." + expiresAt.getEpochSecond();
        return new IssuedRefreshToken(raw, hashRefreshToken(raw), expiresAt);
    }

    public UserPrincipal verifyAccessToken(String token) {
        var payload = verifySigned(token);
        var parts = payload.split("\\|", -1);
        if (parts.length != 5) {
            throw new UnauthorizedException("Invalid access token");
        }
        var expiresAt = Instant.ofEpochSecond(Long.parseLong(parts[4]));
        if (!expiresAt.isAfter(Instant.now())) {
            throw new UnauthorizedException("Access token expired");
        }
        return new UserPrincipal(
                UUID.fromString(parts[0]),
                UUID.fromString(parts[1]),
                parts[2],
                parts[3]
        );
    }

    public String hashRefreshToken(String refreshToken) {
        try {
            var digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(refreshToken.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception ex) {
            throw new IllegalStateException("Unable to hash refresh token", ex);
        }
    }

    private String encodeSigned(String payload) {
        var payload64 = Base64.getUrlEncoder().withoutPadding()
                .encodeToString(payload.getBytes(StandardCharsets.UTF_8));
        return payload64 + "." + sign(payload64);
    }

    private String verifySigned(String token) {
        var parts = token.split("\\.", -1);
        if (parts.length != 2) {
            throw new UnauthorizedException("Invalid access token");
        }
        var expectedSignature = sign(parts[0]);
        if (!MessageDigest.isEqual(
                expectedSignature.getBytes(StandardCharsets.UTF_8),
                parts[1].getBytes(StandardCharsets.UTF_8)
        )) {
            throw new UnauthorizedException("Invalid access token signature");
        }
        return new String(Base64.getUrlDecoder().decode(parts[0]), StandardCharsets.UTF_8);
    }

    private String sign(String payload64) {
        try {
            var mac = Mac.getInstance(HMAC_ALGORITHM);
            mac.init(new SecretKeySpec(properties.jwtSecret().getBytes(StandardCharsets.UTF_8), HMAC_ALGORITHM));
            return Base64.getUrlEncoder().withoutPadding()
                    .encodeToString(mac.doFinal(payload64.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception ex) {
            throw new IllegalStateException("Unable to sign token", ex);
        }
    }
}
