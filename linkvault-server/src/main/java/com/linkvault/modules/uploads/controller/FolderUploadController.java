package com.linkvault.modules.uploads.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.uploads.dto.FolderUploadInitRequest;
import com.linkvault.modules.uploads.dto.FolderUploadInitResponse;
import com.linkvault.modules.uploads.dto.FolderUploadStatusVM;
import com.linkvault.modules.uploads.service.FolderUploadService;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/folder-uploads")
public class FolderUploadController {
    private final FolderUploadService folderUploadService;

    public FolderUploadController(FolderUploadService folderUploadService) {
        this.folderUploadService = folderUploadService;
    }

    @PostMapping
    public ApiResponse<FolderUploadInitResponse> init(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody FolderUploadInitRequest request
    ) {
        return ApiResponse.ok(folderUploadService.init(
                user.userId(),
                user.deviceId(),
                request.parentId(),
                request.folderName(),
                request.fileCount(),
                request.totalBytes()
        ));
    }

    @GetMapping("/{folderUploadId}")
    public ApiResponse<FolderUploadStatusVM> getStatus(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID folderUploadId
    ) {
        return ApiResponse.ok(folderUploadService.getStatus(user.userId(), folderUploadId));
    }

    @PostMapping("/{folderUploadId}/pause")
    public ApiResponse<Void> pause(@CurrentUser UserPrincipal user, @PathVariable UUID folderUploadId) {
        folderUploadService.pause(user.userId(), folderUploadId);
        return ApiResponse.ok(null);
    }

    @PostMapping("/{folderUploadId}/resume")
    public ApiResponse<Void> resume(@CurrentUser UserPrincipal user, @PathVariable UUID folderUploadId) {
        folderUploadService.resume(user.userId(), folderUploadId);
        return ApiResponse.ok(null);
    }

    @PostMapping("/{folderUploadId}/cancel")
    public ApiResponse<Void> cancel(@CurrentUser UserPrincipal user, @PathVariable UUID folderUploadId) {
        folderUploadService.cancel(user.userId(), folderUploadId);
        return ApiResponse.ok(null);
    }
}
