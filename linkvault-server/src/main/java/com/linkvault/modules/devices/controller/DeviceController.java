package com.linkvault.modules.devices.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.devices.dto.DeviceVM;
import com.linkvault.modules.devices.dto.RegisterDeviceCmd;
import com.linkvault.modules.devices.dto.ReportDeviceRequest;
import com.linkvault.modules.devices.service.DeviceService;
import com.linkvault.modules.auth.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.UUID;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/devices")
public class DeviceController {
    private final DeviceService deviceService;
    private final AuthService authService;

    public DeviceController(DeviceService deviceService, AuthService authService) {
        this.deviceService = deviceService;
        this.authService = authService;
    }

    @GetMapping
    public ApiResponse<List<DeviceVM>> list(@CurrentUser UserPrincipal user) {
        return ApiResponse.ok(deviceService.listDevices(user.userId(), user.deviceId()));
    }

    @PostMapping("/current")
    public ApiResponse<DeviceVM> reportCurrent(
            @CurrentUser UserPrincipal user,
            @RequestBody ReportDeviceRequest request,
            HttpServletRequest httpRequest
    ) {
        var vm = deviceService.registerOrTouchDevice(new RegisterDeviceCmd(
                user.userId(),
                user.deviceId(),
                request.deviceName(),
                request.platform(),
                request.appVersion(),
                httpRequest.getRemoteAddr()
        ));
        return ApiResponse.ok(vm);
    }

    @DeleteMapping("/{deviceId}")
    public ApiResponse<Void> revoke(@CurrentUser UserPrincipal user, @PathVariable UUID deviceId) {
        authService.logoutDevice(user.userId(), deviceId);
        return ApiResponse.ok(null);
    }
}
