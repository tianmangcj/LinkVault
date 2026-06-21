package com.linkvault.modules.auth.service;

import com.anji.captcha.model.common.ResponseModel;
import com.anji.captcha.model.vo.CaptchaVO;
import com.linkvault.common.exception.BusinessException;
import com.linkvault.modules.auth.dto.CaptchaCheckResult;
import com.linkvault.modules.auth.dto.CaptchaResult;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class AuthCaptchaService {
    private static final String DEFAULT_CAPTCHA_TYPE = "blockPuzzle";

    private final com.anji.captcha.service.CaptchaService captchaService;

    public AuthCaptchaService(com.anji.captcha.service.CaptchaService captchaService) {
        this.captchaService = captchaService;
    }

    public CaptchaResult createCaptcha() {
        var captcha = new CaptchaVO();
        captcha.setCaptchaType(DEFAULT_CAPTCHA_TYPE);
        var response = captchaService.get(captcha);
        if (!isSuccess(response)) {
            throw captchaError(response);
        }
        var data = responseCaptcha(response);
        return new CaptchaResult(
                nullToEmpty(data.getToken()),
                nullToEmpty(data.getOriginalImageBase64()),
                nullToEmpty(data.getJigsawImageBase64()),
                nullToEmpty(data.getSecretKey())
        );
    }

    public CaptchaCheckResult checkCaptcha(String token, String pointJson) {
        var captcha = new CaptchaVO();
        captcha.setCaptchaType(DEFAULT_CAPTCHA_TYPE);
        captcha.setToken(token);
        captcha.setPointJson(pointJson);
        var response = captchaService.check(captcha);
        if (!isSuccess(response)) {
            throw captchaError(response);
        }
        return new CaptchaCheckResult(token + "---" + pointJson);
    }

    public void verifyCaptcha(String captchaVerification) {
        var captcha = new CaptchaVO();
        captcha.setCaptchaVerification(captchaVerification);
        captcha.setCaptchaType(DEFAULT_CAPTCHA_TYPE);
        var response = captchaService.verification(captcha);
        if (!isSuccess(response)) {
            throw captchaError(response);
        }
    }

    private boolean isSuccess(ResponseModel response) {
        return "0000".equals(response.getRepCode());
    }

    @SuppressWarnings("unchecked")
    private CaptchaVO responseCaptcha(ResponseModel response) {
        var data = response.getRepData();
        if (data instanceof CaptchaVO captcha) {
            return captcha;
        }
        if (data instanceof Map<?, ?> map) {
            var values = (Map<String, Object>) map;
            var captcha = new CaptchaVO();
            captcha.setToken(value(values, "token"));
            captcha.setOriginalImageBase64(value(values, "originalImageBase64"));
            captcha.setJigsawImageBase64(value(values, "jigsawImageBase64"));
            captcha.setSecretKey(value(values, "secretKey"));
            return captcha;
        }
        throw captchaError(response);
    }

    private String value(Map<String, Object> data, String key) {
        var value = data.get(key);
        return value == null ? "" : value.toString();
    }

    private String nullToEmpty(String value) {
        return value == null ? "" : value;
    }

    private BusinessException captchaError(ResponseModel response) {
        var message = response.getRepMsg();
        if (message == null || message.isBlank()) {
            message = "Invalid captcha";
        }
        return new BusinessException("invalid_captcha", message, HttpStatus.BAD_REQUEST);
    }
}
