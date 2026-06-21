package com.linkvault.modules.files.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.response.PageResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.files.domain.FileNodeType;
import com.linkvault.modules.files.dto.BatchFileActionResponse;
import com.linkvault.modules.files.dto.BatchFileIdsRequest;
import com.linkvault.modules.files.dto.BatchMoveFileRequest;
import com.linkvault.modules.files.dto.CopyFileRequest;
import com.linkvault.modules.files.dto.CreateFolderCmd;
import com.linkvault.modules.files.dto.CreateFolderRequest;
import com.linkvault.modules.files.dto.FileNodeVM;
import com.linkvault.modules.files.dto.ListFilesQuery;
import com.linkvault.modules.files.dto.MoveFileRequest;
import com.linkvault.modules.files.dto.RenameFileRequest;
import com.linkvault.modules.files.service.FileService;
import jakarta.validation.Valid;
import java.util.UUID;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/files")
public class FileController {
    private final FileService fileService;

    public FileController(FileService fileService) {
        this.fileService = fileService;
    }

    @GetMapping
    public ApiResponse<PageResponse<FileNodeVM>> list(
            @CurrentUser UserPrincipal user,
            @RequestParam(required = false) UUID parentId,
            @RequestParam(required = false) String type,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int perPage
    ) {
        return ApiResponse.ok(fileService.listFiles(new ListFilesQuery(
                user.userId(),
                parentId,
                FileNodeType.from(type),
                page,
                perPage
        )));
    }

    @GetMapping("/search")
    public ApiResponse<PageResponse<FileNodeVM>> search(
            @CurrentUser UserPrincipal user,
            @RequestParam(defaultValue = "") String q,
            @RequestParam(defaultValue = "files") String scope,
            @RequestParam(required = false) UUID parentId,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int perPage
    ) {
        return ApiResponse.ok(fileService.search(user.userId(), q, scope, parentId, page, perPage));
    }

    @GetMapping("/{fileId}")
    public ApiResponse<FileNodeVM> get(@CurrentUser UserPrincipal user, @PathVariable UUID fileId) {
        return ApiResponse.ok(fileService.getFile(user.userId(), fileId));
    }

    @PostMapping("/folders")
    public ApiResponse<FileNodeVM> createFolder(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody CreateFolderRequest request
    ) {
        return ApiResponse.ok(fileService.createFolder(new CreateFolderCmd(
                user.userId(),
                request.parentId(),
                request.name()
        )));
    }

    @PatchMapping("/{fileId}/rename")
    public ApiResponse<FileNodeVM> rename(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID fileId,
            @Valid @RequestBody RenameFileRequest request
    ) {
        return ApiResponse.ok(fileService.rename(user.userId(), fileId, request.name()));
    }

    @PatchMapping("/{fileId}/move")
    public ApiResponse<FileNodeVM> move(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID fileId,
            @RequestBody MoveFileRequest request
    ) {
        return ApiResponse.ok(fileService.move(user.userId(), fileId, request.parentId()));
    }

    @PostMapping("/{fileId}/copy")
    public ApiResponse<FileNodeVM> copy(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID fileId,
            @RequestBody CopyFileRequest request
    ) {
        return ApiResponse.ok(fileService.copy(user.userId(), fileId, request.parentId()));
    }

    @DeleteMapping("/{fileId}")
    public ApiResponse<Void> recycle(@CurrentUser UserPrincipal user, @PathVariable UUID fileId) {
        fileService.recycle(user.userId(), fileId);
        return ApiResponse.ok(null);
    }

    @PatchMapping("/batch-move")
    public ApiResponse<BatchFileActionResponse> batchMove(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody BatchMoveFileRequest request
    ) {
        return ApiResponse.ok(fileService.moveBatch(user.userId(), request.fileIds(), request.parentId()));
    }

    @PostMapping("/batch-copy")
    public ApiResponse<BatchFileActionResponse> batchCopy(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody BatchMoveFileRequest request
    ) {
        return ApiResponse.ok(fileService.copyBatch(user.userId(), request.fileIds(), request.parentId()));
    }

    @PostMapping("/batch-recycle")
    public ApiResponse<BatchFileActionResponse> batchRecycle(
            @CurrentUser UserPrincipal user,
            @Valid @RequestBody BatchFileIdsRequest request
    ) {
        return ApiResponse.ok(fileService.recycleBatch(user.userId(), request.fileIds()));
    }
}
