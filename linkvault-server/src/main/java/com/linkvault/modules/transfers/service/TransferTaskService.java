package com.linkvault.modules.transfers.service;

import com.linkvault.common.response.PageResponse;
import com.linkvault.modules.downloads.repository.DownloadTaskRepository;
import com.linkvault.modules.storage.service.LocalObjectStore;
import com.linkvault.modules.transfers.domain.TransferDirection;
import com.linkvault.modules.transfers.domain.TransferTaskEntity;
import com.linkvault.modules.transfers.domain.TransferTaskStatus;
import com.linkvault.modules.transfers.domain.TransferTaskType;
import com.linkvault.modules.transfers.dto.CreateTransferTaskCmd;
import com.linkvault.modules.transfers.dto.ListTransferTasksQuery;
import com.linkvault.modules.transfers.dto.TransferTaskVM;
import com.linkvault.modules.transfers.dto.UpdateTransferProgressCmd;
import com.linkvault.modules.transfers.repository.TransferTaskRepository;
import com.linkvault.modules.uploads.domain.UploadTaskStatus;
import com.linkvault.modules.uploads.repository.FolderUploadTaskRepository;
import com.linkvault.modules.uploads.repository.UploadTaskRepository;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.util.UUID;
import org.springframework.core.env.Environment;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TransferTaskService {
    private final TransferTaskRepository transferTaskRepository;
    private final UploadTaskRepository uploadTaskRepository;
    private final FolderUploadTaskRepository folderUploadTaskRepository;
    private final DownloadTaskRepository downloadTaskRepository;
    private final LocalObjectStore localObjectStore;
    private final Path resumableUploadDirectory;

    public TransferTaskService(
            TransferTaskRepository transferTaskRepository,
            UploadTaskRepository uploadTaskRepository,
            FolderUploadTaskRepository folderUploadTaskRepository,
            DownloadTaskRepository downloadTaskRepository,
            LocalObjectStore localObjectStore,
            Environment environment
    ) {
        this.transferTaskRepository = transferTaskRepository;
        this.uploadTaskRepository = uploadTaskRepository;
        this.folderUploadTaskRepository = folderUploadTaskRepository;
        this.downloadTaskRepository = downloadTaskRepository;
        this.localObjectStore = localObjectStore;
        this.resumableUploadDirectory = Path.of(
                environment.getProperty(
                        "linkvault.uploads.temp-dir",
                        System.getProperty("java.io.tmpdir") + "/linkvault-uploads"
                )
        );
    }

    @Transactional
    public TransferTaskVM createTask(CreateTransferTaskCmd cmd) {
        var existing = transferTaskRepository.findByUserIdAndDeviceIdAndSourceIdAndHiddenAtIsNull(
                cmd.userId(),
                cmd.deviceId(),
                cmd.sourceId()
        );
        if (existing.isPresent()) {
            return toVm(existing.get());
        }
        var task = TransferTaskEntity.create(
                cmd.userId(),
                cmd.deviceId(),
                cmd.direction(),
                cmd.taskType(),
                cmd.sourceId(),
                cmd.title(),
                cmd.totalBytes()
        );
        return toVm(transferTaskRepository.save(task));
    }

    @Transactional(readOnly = true)
    public PageResponse<TransferTaskVM> listTasks(ListTransferTasksQuery query) {
        var pageable = PageRequest.of(Math.max(0, query.page() - 1), Math.max(1, Math.min(query.perPage(), 100)));
        var page = query.status() == null
                ? transferTaskRepository.findByUserIdAndDeviceIdAndDirectionAndHiddenAtIsNullOrderByCreatedAtDesc(
                        query.userId(),
                        query.deviceId(),
                        query.direction(),
                        pageable
                )
                : transferTaskRepository.findByUserIdAndDeviceIdAndDirectionAndStatusAndHiddenAtIsNullOrderByCreatedAtDesc(
                        query.userId(),
                        query.deviceId(),
                        query.direction(),
                        query.status(),
                        pageable
                );
        return PageResponse.from(page, this::toVm);
    }

    @Transactional
    public void updateProgress(UpdateTransferProgressCmd cmd) {
        transferTaskRepository.getByIdAndUserIdAndDeviceId(
                cmd.taskId(),
                cmd.userId(),
                cmd.deviceId()
        ).updateProgress(cmd.transferredBytes());
    }

    @Transactional
    public void updateProgressBySource(UUID userId, UUID sourceId, long transferredBytes) {
        transferTaskRepository.findByUserIdAndSourceIdAndHiddenAtIsNull(userId, sourceId)
                .ifPresent(task -> task.updateProgress(transferredBytes));
    }

    @Transactional
    public void pauseTask(UUID userId, UUID deviceId, UUID taskId) {
        var task = transferTaskRepository.getByIdAndUserIdAndDeviceId(taskId, userId, deviceId);
        task.pause();
        pauseSourceTask(task);
    }

    @Transactional
    public void resumeTask(UUID userId, UUID deviceId, UUID taskId) {
        var task = transferTaskRepository.getByIdAndUserIdAndDeviceId(taskId, userId, deviceId);
        task.resume();
        resumeSourceTask(task);
    }

    @Transactional
    public int pauseAll(UUID userId, UUID deviceId) {
        var updated = 0;
        var tasks = transferTaskRepository.findByUserIdAndDeviceIdAndHiddenAtIsNull(userId, deviceId);
        for (var task : tasks) {
            var status = task.getStatus();
            task.pause();
            if (task.getStatus() != status) {
                pauseSourceTask(task);
                updated++;
            }
        }
        return updated;
    }

    @Transactional
    public int resumeAll(UUID userId, UUID deviceId) {
        var updated = 0;
        var tasks = transferTaskRepository.findByUserIdAndDeviceIdAndHiddenAtIsNull(userId, deviceId);
        for (var task : tasks) {
            var status = task.getStatus();
            task.resume();
            if (task.getStatus() != status) {
                resumeSourceTask(task);
                updated++;
            }
        }
        return updated;
    }

    @Transactional
    public void cancelTask(UUID userId, UUID deviceId, UUID taskId) {
        var task = transferTaskRepository.getByIdAndUserIdAndDeviceId(taskId, userId, deviceId);
        cancelSourceTask(task);
        task.cancel();
    }

    @Transactional
    public void deleteTask(UUID userId, UUID deviceId, UUID taskId) {
        deleteTask(transferTaskRepository.getByIdAndUserIdAndDeviceId(taskId, userId, deviceId), Instant.now());
    }

    @Transactional
    public int clear(UUID userId, UUID deviceId, TransferDirection direction) {
        var now = Instant.now();
        var tasks = transferTaskRepository.findByUserIdAndDeviceIdAndDirectionAndHiddenAtIsNull(
                userId,
                deviceId,
                direction
        );
        tasks.forEach(task -> deleteTask(task, now));
        return tasks.size();
    }

    private void deleteTask(TransferTaskEntity task, Instant now) {
        cancelSourceTask(task);
        task.cancel();
        task.hide(now);
    }

    private void cancelSourceTask(TransferTaskEntity task) {
        if (task.getDirection() == TransferDirection.UPLOAD) {
            cancelUploadSource(task);
            return;
        }
        if (task.getDirection() == TransferDirection.DOWNLOAD) {
            downloadTaskRepository.findByIdAndUserId(task.getSourceId(), task.getUserId())
                    .ifPresent(downloadTask -> downloadTask.cancel());
        }
    }

    private void pauseSourceTask(TransferTaskEntity task) {
        if (task.getDirection() == TransferDirection.UPLOAD) {
            pauseUploadSource(task);
            return;
        }
        if (task.getDirection() == TransferDirection.DOWNLOAD) {
            downloadTaskRepository.findByIdAndUserId(task.getSourceId(), task.getUserId())
                    .ifPresent(downloadTask -> downloadTask.pause());
        }
    }

    private void resumeSourceTask(TransferTaskEntity task) {
        if (task.getDirection() == TransferDirection.UPLOAD) {
            resumeUploadSource(task);
            return;
        }
        if (task.getDirection() == TransferDirection.DOWNLOAD) {
            downloadTaskRepository.findByIdAndUserId(task.getSourceId(), task.getUserId())
                    .ifPresent(downloadTask -> downloadTask.resume());
        }
    }

    private void cancelUploadSource(TransferTaskEntity task) {
        if (task.getTaskType() == TransferTaskType.FOLDER) {
            folderUploadTaskRepository.findByIdAndUserId(task.getSourceId(), task.getUserId())
                    .ifPresent(folderUpload -> {
                        folderUpload.cancel();
                        if (folderUpload.getStatus() != UploadTaskStatus.DONE) {
                            folderUploadTaskRepository.delete(folderUpload);
                        }
                    });
            return;
        }
        uploadTaskRepository.findByIdAndUserId(task.getSourceId(), task.getUserId())
                .ifPresent(uploadTask -> {
                    var status = uploadTask.getStatus();
                    uploadTask.cancel();
                    if (status != UploadTaskStatus.DONE) {
                        cleanupUploadObject(uploadTask.getObjectKey());
                        cleanupResumableUpload(task.getUserId(), uploadTask.getId());
                        uploadTaskRepository.delete(uploadTask);
                    }
                });
    }

    private void pauseUploadSource(TransferTaskEntity task) {
        if (task.getTaskType() == TransferTaskType.FOLDER) {
            folderUploadTaskRepository.findByIdAndUserId(task.getSourceId(), task.getUserId())
                    .ifPresent(folderUpload -> folderUpload.pause());
            return;
        }
        uploadTaskRepository.findByIdAndUserId(task.getSourceId(), task.getUserId())
                .ifPresent(uploadTask -> uploadTask.pause());
    }

    private void resumeUploadSource(TransferTaskEntity task) {
        if (task.getTaskType() == TransferTaskType.FOLDER) {
            folderUploadTaskRepository.findByIdAndUserId(task.getSourceId(), task.getUserId())
                    .ifPresent(folderUpload -> folderUpload.resume());
            return;
        }
        uploadTaskRepository.findByIdAndUserId(task.getSourceId(), task.getUserId())
                .ifPresent(uploadTask -> uploadTask.resume());
    }

    private void cleanupUploadObject(String objectKey) {
        try {
            localObjectStore.deleteIfExists(objectKey);
        } catch (RuntimeException ignored) {
            // The task record should still be deleted if residual object cleanup fails.
        }
    }

    private void cleanupResumableUpload(UUID userId, UUID uploadId) {
        try {
            Files.deleteIfExists(resumableUploadDirectory.resolve(userId.toString()).resolve(uploadId + ".part"));
        } catch (IOException ignored) {
            // The task record should still be deleted if residual local cleanup fails.
        }
    }

    @Transactional
    public void completeBySource(UUID userId, UUID sourceId) {
        transferTaskRepository.findByUserIdAndSourceIdAndHiddenAtIsNull(userId, sourceId).ifPresent(TransferTaskEntity::complete);
    }

    @Transactional
    public void pauseBySource(UUID userId, UUID sourceId) {
        transferTaskRepository.findByUserIdAndSourceIdAndHiddenAtIsNull(userId, sourceId).ifPresent(TransferTaskEntity::pause);
    }

    @Transactional
    public void resumeBySource(UUID userId, UUID sourceId) {
        transferTaskRepository.findByUserIdAndSourceIdAndHiddenAtIsNull(userId, sourceId).ifPresent(TransferTaskEntity::resume);
    }

    @Transactional
    public void cancelBySource(UUID userId, UUID sourceId) {
        transferTaskRepository.findByUserIdAndSourceIdAndHiddenAtIsNull(userId, sourceId).ifPresent(TransferTaskEntity::cancel);
    }

    @Transactional
    public void failBySource(UUID userId, UUID sourceId, String reason) {
        transferTaskRepository.findByUserIdAndSourceIdAndHiddenAtIsNull(userId, sourceId)
                .ifPresent(task -> task.fail(reason));
    }

    public TransferTaskVM toVm(TransferTaskEntity task) {
        var progress = task.getTotalBytes() <= 0
                ? 0
                : (double) task.getTransferredBytes() / (double) task.getTotalBytes();
        return new TransferTaskVM(
                task.getId(),
                task.getDeviceId(),
                task.getDirection().name().toLowerCase(),
                task.getTaskType().name().toLowerCase(),
                task.getSourceId(),
                task.getTitle(),
                task.getTotalBytes(),
                task.getTransferredBytes(),
                progress,
                task.getStatus().name().toLowerCase(),
                task.getFailureReason(),
                task.getCreatedAt(),
                task.getUpdatedAt(),
                task.getCompletedAt()
        );
    }
}
