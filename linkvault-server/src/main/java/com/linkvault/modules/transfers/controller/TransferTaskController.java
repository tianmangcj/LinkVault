package com.linkvault.modules.transfers.controller;

import com.linkvault.common.response.ApiResponse;
import com.linkvault.common.response.PageResponse;
import com.linkvault.common.security.CurrentUser;
import com.linkvault.common.security.UserPrincipal;
import com.linkvault.modules.transfers.domain.TransferDirection;
import com.linkvault.modules.transfers.domain.TransferTaskStatus;
import com.linkvault.modules.transfers.dto.ClearTransferTasksResult;
import com.linkvault.modules.transfers.dto.ListTransferTasksQuery;
import com.linkvault.modules.transfers.dto.TransferTaskVM;
import com.linkvault.modules.transfers.dto.UpdateTransferProgressCmd;
import com.linkvault.modules.transfers.dto.UpdateTransferProgressRequest;
import com.linkvault.modules.transfers.service.TransferTaskService;
import jakarta.validation.Valid;
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
@RequestMapping("/api/v1/transfer-tasks")
public class TransferTaskController {
    private final TransferTaskService transferTaskService;

    public TransferTaskController(TransferTaskService transferTaskService) {
        this.transferTaskService = transferTaskService;
    }

    @GetMapping
    public ApiResponse<PageResponse<TransferTaskVM>> list(
            @CurrentUser UserPrincipal user,
            @RequestParam(defaultValue = "upload") String direction,
            @RequestParam(required = false) String status,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int perPage
    ) {
        return ApiResponse.ok(transferTaskService.listTasks(new ListTransferTasksQuery(
                user.userId(),
                user.deviceId(),
                TransferDirection.from(direction),
                TransferTaskStatus.from(status),
                page,
                perPage
        )));
    }

    @PostMapping("/{taskId:[0-9a-fA-F\\-]+}/progress")
    public ApiResponse<Void> progress(
            @CurrentUser UserPrincipal user,
            @PathVariable UUID taskId,
            @Valid @RequestBody UpdateTransferProgressRequest request
    ) {
        transferTaskService.updateProgress(new UpdateTransferProgressCmd(
                user.userId(),
                user.deviceId(),
                taskId,
                request.transferredBytes()
        ));
        return ApiResponse.ok(null);
    }

    @PostMapping("/{taskId:[0-9a-fA-F\\-]+}/pause")
    public ApiResponse<Void> pause(@CurrentUser UserPrincipal user, @PathVariable UUID taskId) {
        transferTaskService.pauseTask(user.userId(), user.deviceId(), taskId);
        return ApiResponse.ok(null);
    }

    @PostMapping("/{taskId:[0-9a-fA-F\\-]+}/resume")
    public ApiResponse<Void> resume(@CurrentUser UserPrincipal user, @PathVariable UUID taskId) {
        transferTaskService.resumeTask(user.userId(), user.deviceId(), taskId);
        return ApiResponse.ok(null);
    }

    @PostMapping("/pause-all")
    public ApiResponse<Void> pauseAll(@CurrentUser UserPrincipal user) {
        transferTaskService.pauseAll(user.userId(), user.deviceId());
        return ApiResponse.ok(null);
    }

    @PostMapping("/resume-all")
    public ApiResponse<Void> resumeAll(@CurrentUser UserPrincipal user) {
        transferTaskService.resumeAll(user.userId(), user.deviceId());
        return ApiResponse.ok(null);
    }

    @PostMapping("/{taskId:[0-9a-fA-F\\-]+}/cancel")
    public ApiResponse<Void> cancel(@CurrentUser UserPrincipal user, @PathVariable UUID taskId) {
        transferTaskService.cancelTask(user.userId(), user.deviceId(), taskId);
        return ApiResponse.ok(null);
    }

    @DeleteMapping("/{taskId:[0-9a-fA-F\\-]+}")
    public ApiResponse<Void> delete(@CurrentUser UserPrincipal user, @PathVariable UUID taskId) {
        transferTaskService.deleteTask(user.userId(), user.deviceId(), taskId);
        return ApiResponse.ok(null);
    }

    @DeleteMapping
    public ApiResponse<ClearTransferTasksResult> clear(
            @CurrentUser UserPrincipal user,
            @RequestParam(defaultValue = "upload") String direction
    ) {
        var cleared = transferTaskService.clear(user.userId(), user.deviceId(), TransferDirection.from(direction));
        return ApiResponse.ok(new ClearTransferTasksResult(cleared));
    }

    @DeleteMapping("/completed")
    public ApiResponse<ClearTransferTasksResult> clearCompleted(
            @CurrentUser UserPrincipal user,
            @RequestParam(defaultValue = "upload") String direction
    ) {
        var cleared = transferTaskService.clear(user.userId(), user.deviceId(), TransferDirection.from(direction));
        return ApiResponse.ok(new ClearTransferTasksResult(cleared));
    }
}
