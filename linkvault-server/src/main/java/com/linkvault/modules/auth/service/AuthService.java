package com.linkvault.modules.auth.service;

import com.linkvault.common.exception.BusinessException;
import com.linkvault.common.exception.UnauthorizedException;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.auth.domain.RefreshTokenEntity;
import com.linkvault.modules.auth.dto.AuthResult;
import com.linkvault.modules.auth.dto.LoginCmd;
import com.linkvault.modules.auth.dto.LogoutCmd;
import com.linkvault.modules.auth.dto.RefreshTokenCmd;
import com.linkvault.modules.auth.dto.RegisterCmd;
import com.linkvault.modules.auth.repository.RefreshTokenRepository;
import com.linkvault.modules.devices.dto.RegisterDeviceCmd;
import com.linkvault.modules.devices.service.DeviceService;
import com.linkvault.modules.quota.service.QuotaService;
import com.linkvault.modules.users.dto.CreateUserCmd;
import com.linkvault.modules.users.repository.UserRepository;
import com.linkvault.modules.users.service.UserService;
import java.time.Instant;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {
    private final UserRepository userRepository;
    private final UserService userService;
    private final QuotaService quotaService;
    private final DeviceService deviceService;
    private final AuthCaptchaService captchaService;
    private final JwtTokenService jwtTokenService;
    private final RefreshTokenRepository refreshTokenRepository;
    private final PasswordEncoder passwordEncoder;

    public AuthService(
            UserRepository userRepository,
            UserService userService,
            QuotaService quotaService,
            DeviceService deviceService,
            AuthCaptchaService captchaService,
            JwtTokenService jwtTokenService,
            RefreshTokenRepository refreshTokenRepository,
            PasswordEncoder passwordEncoder
    ) {
        this.userRepository = userRepository;
        this.userService = userService;
        this.quotaService = quotaService;
        this.deviceService = deviceService;
        this.captchaService = captchaService;
        this.jwtTokenService = jwtTokenService;
        this.refreshTokenRepository = refreshTokenRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Transactional
    public AuthResult register(RegisterCmd cmd) {
        if (!cmd.password().equals(cmd.confirmPassword())) {
            throw new BusinessException("validation_error", "Passwords do not match", HttpStatus.BAD_REQUEST);
        }
        captchaService.verifyCaptcha(cmd.captchaVerification());
        var profile = userService.createUser(new CreateUserCmd(cmd.username(), cmd.password()));
        quotaService.initializeQuota(profile.id());
        var device = deviceService.registerOrTouchDevice(new RegisterDeviceCmd(
                profile.id(),
                null,
                cmd.deviceName(),
                cmd.platform(),
                cmd.appVersion(),
                cmd.ipAddress()
        ));
        return issue(profile, device);
    }

    @Transactional
    public AuthResult login(LoginCmd cmd) {
        captchaService.verifyCaptcha(cmd.captchaVerification());
        var user = userRepository.findByAccount(cmd.account())
                .orElseThrow(() -> new UnauthorizedException("invalid_credentials", "Invalid account or password"));
        if (!user.isActive() || !user.passwordMatches(passwordEncoder, cmd.password())) {
            throw new UnauthorizedException("invalid_credentials", "Invalid account or password");
        }
        quotaService.initializeQuota(user.getId());
        var device = deviceService.registerOrTouchDevice(new RegisterDeviceCmd(
                user.getId(),
                null,
                cmd.deviceName(),
                cmd.platform(),
                cmd.appVersion(),
                cmd.ipAddress()
        ));
        return issue(userService.toProfile(user), device);
    }

    @Transactional
    public AuthResult refresh(RefreshTokenCmd cmd) {
        var tokenHash = jwtTokenService.hashRefreshToken(cmd.refreshToken());
        var refreshToken = refreshTokenRepository.findByTokenHash(tokenHash)
                .orElseThrow(() -> new UnauthorizedException("Invalid refresh token"));
        var now = Instant.now();
        if (refreshToken.isRevoked() || refreshToken.isExpired(now)) {
            throw new UnauthorizedException("Invalid refresh token");
        }
        refreshToken.revoke(now);
        var user = userRepository.getByIdOrThrow(refreshToken.getUserId());
        var profile = userService.toProfile(user);
        if (!deviceService.isDeviceActive(user.getId(), refreshToken.getDeviceId())) {
            throw new UnauthorizedException("Device is no longer active");
        }
        var device = deviceService.touchLogin(user.getId(), refreshToken.getDeviceId());
        return issue(profile, device);
    }

    @Transactional
    public void logout(LogoutCmd cmd) {
        logoutDevice(cmd.userId(), cmd.deviceId());
    }

    @Transactional
    public void logoutDevice(java.util.UUID userId, java.util.UUID deviceId) {
        refreshTokenRepository.findByUserIdAndDeviceIdAndRevokedAtIsNull(userId, deviceId)
                .forEach(token -> token.revoke(Instant.now()));
        deviceService.revokeDevice(userId, deviceId);
    }

    private AuthResult issue(com.linkvault.modules.users.dto.UserProfileVM user,
                             com.linkvault.modules.devices.dto.DeviceVM device) {
        var principal = new UserPrincipal(user.id(), device.id(), user.username(), user.role());
        var accessToken = jwtTokenService.issueAccessToken(principal);
        var refreshToken = jwtTokenService.issueRefreshToken(user.id(), device.id());
        refreshTokenRepository.save(RefreshTokenEntity.create(
                user.id(),
                device.id(),
                refreshToken.tokenHash(),
                refreshToken.expiresAt()
        ));
        return new AuthResult(
                accessToken.token(),
                refreshToken.token(),
                accessToken.expiresAt(),
                refreshToken.expiresAt(),
                user,
                device
        );
    }

}
