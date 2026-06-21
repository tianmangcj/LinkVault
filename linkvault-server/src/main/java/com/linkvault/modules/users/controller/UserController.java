package com.linkvault.modules.users.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.users.dto.ChangePasswordRequest;
import com.linkvault.modules.users.dto.UpdateAvatarRequest;
import com.linkvault.modules.users.dto.UpdateProfileCmd;
import com.linkvault.modules.users.dto.UpdateProfileRequest;
import com.linkvault.modules.users.dto.UpdateUsernameRequest;
import com.linkvault.modules.users.dto.UserProfileVM;
import com.linkvault.modules.users.service.UserService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/users")
public class UserController {
    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    @GetMapping("/me")
    public ApiResponse<UserProfileVM> me(@CurrentUser UserPrincipal user) {
        return ApiResponse.ok(userService.getCurrentUser(user.userId()));
    }

    @PatchMapping("/me")
    public ApiResponse<UserProfileVM> updateMe(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody UpdateProfileRequest request
    ) {
        var profile = userService.updateProfile(
                user.userId(),
                new UpdateProfileCmd(request.displayName(), request.avatarText())
        );
        return ApiResponse.ok(profile);
    }

    @PatchMapping("/me/username")
    public ApiResponse<UserProfileVM> updateUsername(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody UpdateUsernameRequest request
    ) {
        return ApiResponse.ok(userService.updateUsername(user.userId(), request.username()));
    }

    @PatchMapping("/me/avatar")
    public ApiResponse<UserProfileVM> updateAvatar(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody UpdateAvatarRequest request
    ) {
        return ApiResponse.ok(userService.updateAvatar(user.userId(), request.avatarImageData()));
    }

    @PatchMapping("/me/password")
    public ApiResponse<Void> changePassword(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody ChangePasswordRequest request
    ) {
        userService.changePassword(
                user.userId(),
                request.oldPassword(),
                request.newPassword(),
                request.confirmPassword()
        );
        return ApiResponse.ok(null);
    }

    @DeleteMapping("/me")
    public ApiResponse<Void> deleteAccount(@CurrentUser UserPrincipal user) {
        userService.deleteAccount(user.userId());
        return ApiResponse.ok(null);
    }
}
