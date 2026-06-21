package com.linkvault.modules.uploads.service;

import com.linkvault.modules.quota.service.QuotaService;
import com.linkvault.modules.transfers.domain.TransferDirection;
import com.linkvault.modules.transfers.domain.TransferTaskType;
import com.linkvault.modules.transfers.dto.CreateTransferTaskCmd;
import com.linkvault.modules.transfers.service.TransferTaskService;
import com.linkvault.modules.uploads.domain.FolderUploadTaskEntity;
import com.linkvault.modules.uploads.dto.FolderUploadInitResponse;
import com.linkvault.modules.uploads.dto.FolderUploadStatusVM;
import com.linkvault.modules.uploads.repository.FolderUploadTaskRepository;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class FolderUploadService {
    private final FolderUploadTaskRepository folderUploadTaskRepository;
    private final QuotaService quotaService;
    private final TransferTaskService transferTaskService;

    public FolderUploadService(
            FolderUploadTaskRepository folderUploadTaskRepository,
            QuotaService quotaService,
            TransferTaskService transferTaskService
    ) {
        this.folderUploadTaskRepository = folderUploadTaskRepository;
        this.quotaService = quotaService;
        this.transferTaskService = transferTaskService;
    }

    @Transactional
    public FolderUploadInitResponse init(
            UUID userId,
            UUID deviceId,
            UUID parentId,
            String folderName,
            int fileCount,
            long totalBytes
    ) {
        quotaService.checkCanUpload(userId, totalBytes);
        var task = folderUploadTaskRepository.save(
                FolderUploadTaskEntity.create(userId, parentId, folderName, fileCount, totalBytes)
        );
        transferTaskService.createTask(new CreateTransferTaskCmd(
                userId,
                deviceId,
                TransferDirection.UPLOAD,
                TransferTaskType.FOLDER,
                task.getId(),
                folderName,
                totalBytes
        ));
        return new FolderUploadInitResponse(task.getId(), toVm(task));
    }

    @Transactional(readOnly = true)
    public FolderUploadStatusVM getStatus(UUID userId, UUID folderUploadId) {
        return toVm(folderUploadTaskRepository.getByIdAndUserId(folderUploadId, userId));
    }

    @Transactional
    public void pause(UUID userId, UUID folderUploadId) {
        folderUploadTaskRepository.getByIdAndUserId(folderUploadId, userId).pause();
        transferTaskService.pauseBySource(userId, folderUploadId);
    }

    @Transactional
    public void resume(UUID userId, UUID folderUploadId) {
        folderUploadTaskRepository.getByIdAndUserId(folderUploadId, userId).resume();
        transferTaskService.resumeBySource(userId, folderUploadId);
    }

    @Transactional
    public void cancel(UUID userId, UUID folderUploadId) {
        folderUploadTaskRepository.getByIdAndUserId(folderUploadId, userId).cancel();
        transferTaskService.cancelBySource(userId, folderUploadId);
    }

    private FolderUploadStatusVM toVm(FolderUploadTaskEntity task) {
        return new FolderUploadStatusVM(
                task.getId(),
                task.getFolderName(),
                task.getFileCount(),
                task.getTotalBytes(),
                task.getStatus().name().toLowerCase(),
                task.getCreatedAt(),
                task.getUpdatedAt()
        );
    }
}
