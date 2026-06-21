package com.linkvault.modules.recyclebin.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.response.PageResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.files.dto.FileNodeVM;
import com.linkvault.modules.recyclebin.dto.RestoreFileRequest;
import com.linkvault.modules.recyclebin.service.RecycleBinService;
import java.util.UUID;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/recycle-bin")
public class RecycleBinController {
    private final RecycleBinService recycleBinService;

    public RecycleBinController(RecycleBinService recycleBinService) {
        this.recycleBinService = recycleBinService;
    }

    @GetMapping
    public ApiResponse<PageResponse<FileNodeVM>> list(
            @CurrentUser UserPrincipal user,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int perPage
    ) {
        return ApiResponse.ok(recycleBinService.list(user.userId(), page, perPage));
    }

    @PostMapping("/{fileId}/restore")
    public ApiResponse<FileNodeVM> restore(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID fileId,
            @RequestBody(required = false) RestoreFileRequest request
    ) {
        return ApiResponse.ok(recycleBinService.restore(
                user.userId(),
                fileId,
                request == null || request.useOriginalPath() == null || request.useOriginalPath(),
                request == null ? null : request.parentId()
        ));
    }

    @DeleteMapping("/{fileId}")
    public ApiResponse<Void> purge(@CurrentUser UserPrincipal user, @PathVariable UUID fileId) {
        recycleBinService.purgeOne(user.userId(), fileId);
        return ApiResponse.ok(null);
    }

    @DeleteMapping
    public ApiResponse<Void> empty(@CurrentUser UserPrincipal user) {
        recycleBinService.empty(user.userId());
        return ApiResponse.ok(null);
    }
}
