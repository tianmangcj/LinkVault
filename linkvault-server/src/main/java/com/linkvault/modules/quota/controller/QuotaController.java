package com.linkvault.modules.quota.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.quota.dto.QuotaVM;
import com.linkvault.modules.quota.service.QuotaService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/users/me/quota")
public class QuotaController {
    private final QuotaService quotaService;

    public QuotaController(QuotaService quotaService) {
        this.quotaService = quotaService;
    }

    @GetMapping
    public ApiResponse<QuotaVM> get(@CurrentUser UserPrincipal user) {
        return ApiResponse.ok(quotaService.getQuota(user.userId()));
    }
}
