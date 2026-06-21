package com.linkvault.modules.auth.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.auth.dto.AuthResponse;
import com.linkvault.modules.auth.dto.CaptchaCheckRequest;
import com.linkvault.modules.auth.dto.CaptchaCheckResponse;
import com.linkvault.modules.auth.dto.CaptchaResponse;
import com.linkvault.modules.auth.dto.LoginCmd;
import com.linkvault.modules.auth.dto.LoginRequest;
import com.linkvault.modules.auth.dto.LogoutCmd;
import com.linkvault.modules.auth.dto.LogoutRequest;
import com.linkvault.modules.auth.dto.RefreshTokenCmd;
import com.linkvault.modules.auth.dto.RefreshTokenRequest;
import com.linkvault.modules.auth.dto.RegisterCmd;
import com.linkvault.modules.auth.dto.RegisterRequest;
import com.linkvault.modules.auth.service.AuthCaptchaService;
import com.linkvault.modules.auth.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {
    private final AuthService authService;
    private final AuthCaptchaService captchaService;

    public AuthController(AuthService authService, AuthCaptchaService captchaService) {
        this.authService = authService;
        this.captchaService = captchaService;
    }

    @GetMapping("/captcha")
    public ApiResponse<CaptchaResponse> captcha() {
        var result = captchaService.createCaptcha();
        return ApiResponse.ok(new CaptchaResponse(
                result.token(),
                result.originalImageBase64(),
                result.jigsawImageBase64(),
                result.secretKey()
        ));
    }

    @PostMapping("/captcha/check")
    public ApiResponse<CaptchaCheckResponse> checkCaptcha(@Valid @RequestBody CaptchaCheckRequest request) {
        var result = captchaService.checkCaptcha(request.token(), request.pointJson());
        return ApiResponse.ok(new CaptchaCheckResponse(result.captchaVerification()));
    }

    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<AuthResponse> register(
            @Valid @RequestBody RegisterRequest request,
            HttpServletRequest httpRequest
    ) {
        return ApiResponse.ok(toResponse(authService.register(new RegisterCmd(
                request.username(),
                request.password(),
                request.confirmPassword(),
                request.captchaVerification(),
                request.deviceName(),
                request.platform(),
                request.appVersion(),
                httpRequest.getRemoteAddr()
        ))));
    }

    @PostMapping("/login")
    public ApiResponse<AuthResponse> login(@Valid @RequestBody LoginRequest request, HttpServletRequest httpRequest) {
        return ApiResponse.ok(toResponse(authService.login(new LoginCmd(
                request.account(),
                request.password(),
                request.captchaVerification(),
                request.deviceName(),
                request.platform(),
                request.appVersion(),
                httpRequest.getRemoteAddr()
        ))));
    }

    @PostMapping("/refresh")
    public ApiResponse<AuthResponse> refresh(@Valid @RequestBody RefreshTokenRequest request) {
        return ApiResponse.ok(toResponse(authService.refresh(new RefreshTokenCmd(request.refreshToken()))));
    }

    @PostMapping("/logout")
    public ApiResponse<Void> logout(@CurrentUser UserPrincipal user, @RequestBody LogoutRequest request) {
        authService.logout(new LogoutCmd(user.userId(), user.deviceId(), request == null ? null : request.refreshToken()));
        return ApiResponse.ok(null);
    }

    private AuthResponse toResponse(com.linkvault.modules.auth.dto.AuthResult result) {
        return new AuthResponse(
                result.accessToken(),
                result.refreshToken(),
                result.accessTokenExpiresAt(),
                result.refreshTokenExpiresAt(),
                result.user(),
                result.device()
        );
    }
}
