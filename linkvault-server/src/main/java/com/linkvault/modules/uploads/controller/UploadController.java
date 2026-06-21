package com.linkvault.modules.uploads.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.files.dto.FileNodeVM;
import com.linkvault.modules.uploads.dto.DirectUploadCmd;
import com.linkvault.modules.uploads.dto.DirectUploadInitRequest;
import com.linkvault.modules.uploads.dto.InitUploadCmd;
import com.linkvault.modules.uploads.dto.InitUploadRequest;
import com.linkvault.modules.uploads.dto.InitUploadResponse;
import com.linkvault.modules.uploads.dto.UploadTaskVM;
import com.linkvault.modules.transfers.dto.UpdateTransferProgressRequest;
import com.linkvault.modules.uploads.service.UploadService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/v1/uploads")
public class UploadController {
    private final UploadService uploadService;

    public UploadController(UploadService uploadService) {
        this.uploadService = uploadService;
    }

    @PostMapping
    public ApiResponse<InitUploadResponse> init(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody InitUploadRequest request
    ) {
        return ApiResponse.ok(uploadService.initUpload(new InitUploadCmd(
                user.userId(),
                user.deviceId(),
                request.parentId(),
                request.fileName(),
                request.sizeBytes(),
                request.mimeType(),
                request.sha256()
        )));
    }

    @PostMapping("/direct")
    public ApiResponse<FileNodeVM> direct(
            @CurrentUser UserPrincipal user,
            @RequestParam UUID uploadId,
            @RequestParam(required = false) UUID parentId,
            @RequestParam("file") MultipartFile file
    ) throws java.io.IOException {
        return ApiResponse.ok(uploadService.directUpload(new DirectUploadCmd(
                user.userId(),
                uploadId,
                parentId,
                file.getOriginalFilename(),
                file.getSize(),
                file.getContentType(),
                file.getInputStream()
        )));
    }

    @PostMapping(value = "/direct/chunk", consumes = "application/octet-stream")
    public ApiResponse<FileNodeVM> directChunk(
            @CurrentUser UserPrincipal user,
            @RequestParam UUID uploadId,
            @RequestParam(defaultValue = "0") long offset,
            @RequestParam(defaultValue = "false") boolean complete,
            HttpServletRequest request
    ) throws java.io.IOException {
        return ApiResponse.ok(uploadService.directUploadChunk(
                new com.linkvault.modules.uploads.dto.DirectUploadChunkCmd(
                        user.userId(),
                        uploadId,
                        offset,
                        complete,
                        request.getInputStream()
                )
        ));
    }

    @PostMapping("/direct/init")
    public ApiResponse<UploadTaskVM> initDirect(
            @CurrentUser UserPrincipal user,
            @RequestParam(required = false) UUID parentId,
            @Valid @RequestBody DirectUploadInitRequest request
    ) {
        return ApiResponse.ok(uploadService.initDirectUpload(
                user.userId(),
                user.deviceId(),
                parentId,
                request.fileName(),
                request.sizeBytes(),
                request.mimeType()
        ));
    }

    @PostMapping("/{uploadId}/progress")
    public ApiResponse<Void> progress(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID uploadId,
            @Valid @RequestBody UpdateTransferProgressRequest request
    ) {
        uploadService.reportProgress(user.userId(), uploadId, request.transferredBytes());
        return ApiResponse.ok(null);
    }

    @GetMapping("/{uploadId}")
    public ApiResponse<UploadTaskVM> get(@CurrentUser UserPrincipal user, @PathVariable UUID uploadId) {
        return ApiResponse.ok(uploadService.getTask(user.userId(), uploadId));
    }

    @GetMapping("/{uploadId}/resume")
    public ApiResponse<UploadTaskVM> resumeInfo(@CurrentUser UserPrincipal user, @PathVariable UUID uploadId) {
        return ApiResponse.ok(uploadService.getTask(user.userId(), uploadId));
    }

    @PostMapping("/{uploadId}/complete")
    public ApiResponse<FileNodeVM> complete(@CurrentUser UserPrincipal user, @PathVariable UUID uploadId) {
        return ApiResponse.ok(uploadService.complete(user.userId(), uploadId));
    }

    @PostMapping("/{uploadId}/pause")
    public ApiResponse<Void> pause(@CurrentUser UserPrincipal user, @PathVariable UUID uploadId) {
        uploadService.pause(user.userId(), uploadId);
        return ApiResponse.ok(null);
    }

    @PostMapping("/{uploadId}/resume")
    public ApiResponse<Void> resume(@CurrentUser UserPrincipal user, @PathVariable UUID uploadId) {
        uploadService.resume(user.userId(), uploadId);
        return ApiResponse.ok(null);
    }

    @PostMapping("/{uploadId}/cancel")
    public ApiResponse<Void> cancel(@CurrentUser UserPrincipal user, @PathVariable UUID uploadId) {
        uploadService.cancel(user.userId(), uploadId);
        return ApiResponse.ok(null);
    }
}
