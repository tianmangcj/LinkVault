package com.linkvault.modules.downloads.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.downloads.dto.BatchDownloadRequest;
import com.linkvault.modules.downloads.dto.PrepareDownloadCmd;
import com.linkvault.modules.downloads.dto.PrepareDownloadRequest;
import com.linkvault.modules.downloads.dto.PrepareDownloadResponse;
import com.linkvault.modules.downloads.dto.ReportDownloadProgressRequest;
import com.linkvault.modules.downloads.service.DownloadService;
import jakarta.validation.Valid;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

@RestController
@RequestMapping("/api/v1/downloads")
public class DownloadController {
    private final DownloadService downloadService;

    public DownloadController(DownloadService downloadService) {
        this.downloadService = downloadService;
    }

    @PostMapping
    public ApiResponse<PrepareDownloadResponse> prepare(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody PrepareDownloadRequest request
    ) {
        var result = downloadService.prepareDownload(new PrepareDownloadCmd(
                user.userId(),
                user.deviceId(),
                request.fileId()
        ));
        return ApiResponse.ok(new PrepareDownloadResponse(
                result.downloadTaskId(),
                result.fileId(),
                result.fileName(),
                result.sizeBytes(),
                result.mimeType(),
                result.presignedUrl().url(),
                result.presignedUrl().expiresAt(),
                result.presignedUrl().headers()
        ));
    }

    @PostMapping("/{downloadTaskId}/resume")
    public ApiResponse<PrepareDownloadResponse> resume(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID downloadTaskId
    ) {
        var result = downloadService.resumeDownload(user.userId(), downloadTaskId);
        return ApiResponse.ok(new PrepareDownloadResponse(
                result.downloadTaskId(),
                result.fileId(),
                result.fileName(),
                result.sizeBytes(),
                result.mimeType(),
                result.presignedUrl().url(),
                result.presignedUrl().expiresAt(),
                result.presignedUrl().headers()
        ));
    }

    @GetMapping("/files/{fileId}/stream")
    public ResponseEntity<StreamingResponseBody> stream(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID fileId,
            @RequestParam(defaultValue = "0") long offset
    ) {
        var result = downloadService.streamFile(user.userId(), fileId, offset);
        var contentLength = Math.max(0, result.sizeBytes() - result.offset());
        return ResponseEntity.ok()
                .contentLength(contentLength)
                .contentType(MediaType.parseMediaType(
                        result.mimeType() == null || result.mimeType().isBlank()
                                ? MediaType.APPLICATION_OCTET_STREAM_VALUE
                                : result.mimeType()
                ))
                .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                .header(HttpHeaders.CONTENT_DISPOSITION, attachmentDisposition(result.fileName()))
                .body(result.body());
    }

    @PostMapping("/batch/stream")
    public ResponseEntity<StreamingResponseBody> streamBatch(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody BatchDownloadRequest request
    ) {
        var result = downloadService.streamBatch(user.userId(), user.deviceId(), request.fileIds());
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType("application/zip"))
                .header(HttpHeaders.CONTENT_DISPOSITION, attachmentDisposition(result.fileName()))
                .body(result.body());
    }

    private String attachmentDisposition(String fileName) {
        return ContentDisposition.attachment()
                .filename(fileName, StandardCharsets.UTF_8)
                .build()
                .toString();
    }

    @PostMapping("/{downloadTaskId}/progress")
    public ApiResponse<Void> reportProgress(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID downloadTaskId,
            @Valid @RequestBody ReportDownloadProgressRequest request
    ) {
        downloadService.reportProgress(user.userId(), downloadTaskId, request.downloadedBytes());
        return ApiResponse.ok(null);
    }

    @PostMapping("/{downloadTaskId}/complete")
    public ApiResponse<Void> complete(@CurrentUser UserPrincipal user, @PathVariable UUID downloadTaskId) {
        downloadService.completeDownload(user.userId(), downloadTaskId);
        return ApiResponse.ok(null);
    }

    @PostMapping("/{downloadTaskId}/cancel")
    public ApiResponse<Void> cancel(@CurrentUser UserPrincipal user, @PathVariable UUID downloadTaskId) {
        downloadService.cancelDownload(user.userId(), downloadTaskId);
        return ApiResponse.ok(null);
    }

    @PostMapping("/{downloadTaskId}/pause")
    public ApiResponse<Void> pause(@CurrentUser UserPrincipal user, @PathVariable UUID downloadTaskId) {
        downloadService.pauseDownload(user.userId(), downloadTaskId);
        return ApiResponse.ok(null);
    }
}
