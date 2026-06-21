package com.linkvault.modules.uploads.service;

import com.linkvault.common.exception.BusinessException;
import com.linkvault.modules.files.dto.CreateFileNodeCmd;
import com.linkvault.modules.files.dto.FileNodeVM;
import com.linkvault.modules.files.service.FileService;
import com.linkvault.modules.quota.service.QuotaService;
import com.linkvault.modules.storage.service.LocalObjectStore;
import com.linkvault.modules.storage.service.ObjectStorageClient;
import com.linkvault.modules.storage.service.StorageObjectService;
import com.linkvault.modules.transfers.domain.TransferDirection;
import com.linkvault.modules.transfers.domain.TransferTaskType;
import com.linkvault.modules.transfers.dto.CreateTransferTaskCmd;
import com.linkvault.modules.transfers.service.TransferTaskService;
import com.linkvault.modules.uploads.domain.UploadTaskEntity;
import com.linkvault.modules.uploads.domain.UploadTaskStatus;
import com.linkvault.modules.uploads.dto.DirectUploadChunkCmd;
import com.linkvault.modules.uploads.dto.DirectUploadCmd;
import com.linkvault.modules.uploads.dto.InitUploadCmd;
import com.linkvault.modules.uploads.dto.InitUploadResponse;
import com.linkvault.modules.uploads.dto.PresignedUrlVM;
import com.linkvault.modules.uploads.dto.UploadTaskVM;
import com.linkvault.modules.uploads.repository.UploadTaskRepository;
import java.io.IOException;
import java.io.InputStream;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.DigestInputStream;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;

@Service
public class UploadService {
    private final UploadTaskRepository uploadTaskRepository;
    private final QuotaService quotaService;
    private final StorageObjectService storageObjectService;
    private final ObjectStorageClient objectStorageClient;
    private final LocalObjectStore localObjectStore;
    private final FileService fileService;
    private final TransferTaskService transferTaskService;
    private final Path resumableUploadDirectory;
    private final TransactionTemplate transactionTemplate;

    public UploadService(
            UploadTaskRepository uploadTaskRepository,
            QuotaService quotaService,
            StorageObjectService storageObjectService,
            ObjectStorageClient objectStorageClient,
            LocalObjectStore localObjectStore,
            FileService fileService,
            TransferTaskService transferTaskService,
            TransactionTemplate transactionTemplate,
            org.springframework.core.env.Environment environment
    ) {
        this.uploadTaskRepository = uploadTaskRepository;
        this.quotaService = quotaService;
        this.storageObjectService = storageObjectService;
        this.objectStorageClient = objectStorageClient;
        this.localObjectStore = localObjectStore;
        this.fileService = fileService;
        this.transferTaskService = transferTaskService;
        this.transactionTemplate = transactionTemplate;
        this.resumableUploadDirectory = Path.of(
                environment.getProperty(
                        "linkvault.uploads.temp-dir",
                        System.getProperty("java.io.tmpdir") + "/linkvault-uploads"
                )
        );
    }

    @Transactional
    public InitUploadResponse initUpload(InitUploadCmd cmd) {
        quotaService.checkCanUpload(cmd.userId(), cmd.sizeBytes());
        var dedup = storageObjectService.findDedupCandidate(cmd.sha256(), cmd.sizeBytes());
        if (dedup.isPresent()) {
            return new InitUploadResponse(null, true, null, null);
        }

        var objectKey = cmd.userId() + "/" + UUID.randomUUID() + "/" + cmd.fileName();
        var upload = uploadTaskRepository.save(UploadTaskEntity.create(
                cmd.userId(),
                cmd.parentId(),
                cmd.fileName(),
                cmd.sizeBytes(),
                cmd.mimeType(),
                cmd.sha256(),
                objectKey
        ));
        transferTaskService.createTask(new CreateTransferTaskCmd(
                cmd.userId(),
                cmd.deviceId(),
                TransferDirection.UPLOAD,
                TransferTaskType.FILE,
                upload.getId(),
                cmd.fileName(),
                cmd.sizeBytes()
        ));
        var presigned = objectStorageClient.presignPut(objectKey, cmd.mimeType(), Duration.ofMinutes(30));
        return new InitUploadResponse(
                upload.getId(),
                false,
                new PresignedUrlVM(presigned.url(), presigned.expiresAt(), presigned.headers()),
                toVm(upload)
        );
    }

    @Transactional
    public FileNodeVM directUpload(DirectUploadCmd cmd) {
        var fileName = normalizeFileName(cmd.fileName());
        if (fileName.isBlank()) {
            throw new BusinessException("validation_error", "File name is required", HttpStatus.BAD_REQUEST);
        }
        if (cmd.uploadId() == null) {
            throw new BusinessException("validation_error", "Upload task id is required", HttpStatus.BAD_REQUEST);
        }
        var upload = uploadTaskRepository.getByIdAndUserId(cmd.uploadId(), cmd.userId());
        if (upload.getStatus() == UploadTaskStatus.CANCELED) {
            throw new BusinessException("upload_canceled", "Upload has been canceled", HttpStatus.CONFLICT);
        }
        if (!upload.getFileName().equals(fileName) || upload.getSizeBytes() != cmd.sizeBytes()) {
            throw new BusinessException("validation_error", "Upload task does not match uploaded file", HttpStatus.BAD_REQUEST);
        }
        quotaService.checkCanUpload(cmd.userId(), cmd.sizeBytes());
        fileService.validateCreateFileTarget(cmd.userId(), cmd.parentId(), fileName);

        String sha256;
        try {
            var digest = MessageDigest.getInstance("SHA-256");
            try (var digestStream = new DigestInputStream(cmd.content(), digest)) {
                localObjectStore.save(upload.getObjectKey(), digestStream, cmd.sizeBytes(), cmd.mimeType());
            }
            sha256 = HexFormat.of().formatHex(digest.digest());
        } catch (Exception ex) {
            upload.fail();
            transferTaskService.failBySource(cmd.userId(), upload.getId(), "Unable to store uploaded file");
            throw new BusinessException("storage_error", "Unable to store uploaded file", HttpStatus.INTERNAL_SERVER_ERROR);
        }

        upload.markStored(sha256, cmd.mimeType());
        var object = storageObjectService.createObject(upload.getObjectKey(), sha256, cmd.sizeBytes(), cmd.mimeType());
        var file = fileService.createFile(new CreateFileNodeCmd(
                cmd.userId(),
                cmd.parentId(),
                object.getId(),
                fileName,
                cmd.sizeBytes(),
                cmd.mimeType(),
                sha256
        ));
        quotaService.commitUpload(cmd.userId(), cmd.sizeBytes());
        upload.complete(Instant.now());
        transferTaskService.completeBySource(cmd.userId(), upload.getId());
        return file;
    }

    public FileNodeVM directUploadChunk(DirectUploadChunkCmd cmd) {
        var upload = uploadTaskRepository.getByIdAndUserId(cmd.uploadId(), cmd.userId());
        if (upload.getStatus() == UploadTaskStatus.CANCELED) {
            throw new BusinessException("upload_canceled", "Upload has been canceled", HttpStatus.CONFLICT);
        }
        if (upload.getStatus() == UploadTaskStatus.DONE) {
            throw new BusinessException("validation_error", "Upload is already completed", HttpStatus.BAD_REQUEST);
        }
        quotaService.checkCanUpload(cmd.userId(), upload.getSizeBytes());
        fileService.validateCreateFileTarget(cmd.userId(), upload.getParentId(), upload.getFileName());

        try {
            var tempPath = resumableUploadPath(cmd.userId(), upload.getId());
            Files.createDirectories(tempPath.getParent());
            var existingBytes = Files.exists(tempPath) ? Files.size(tempPath) : 0L;
            if (cmd.offset() < 0 || cmd.offset() > upload.getSizeBytes()) {
                throw new BusinessException("validation_error", "Upload offset is invalid", HttpStatus.BAD_REQUEST);
            }
            if (cmd.offset() != existingBytes) {
                if (cmd.offset() == 0) {
                    Files.deleteIfExists(tempPath);
                    existingBytes = 0;
                    upload.resetProgress();
                    uploadTaskRepository.saveAndFlush(upload);
                } else {
                    throw new BusinessException(
                            "upload_offset_mismatch",
                            "Upload offset does not match server progress",
                            HttpStatus.CONFLICT
                    );
                }
            }
            var transferredBytes = appendUploadChunk(
                    cmd.userId(),
                    upload.getId(),
                    tempPath,
                    cmd.content(),
                    existingBytes,
                    upload.getSizeBytes()
            );
            if (!cmd.complete() || transferredBytes < upload.getSizeBytes()) {
                return null;
            }
            if (transferredBytes != upload.getSizeBytes()) {
                throw new BusinessException("validation_error", "Uploaded bytes do not match task size", HttpStatus.BAD_REQUEST);
            }
            return completeResumableUploadInTransaction(cmd.userId(), upload.getId(), tempPath);
        } catch (BusinessException ex) {
            throw ex;
        } catch (IOException ex) {
            pauseUploadAfterChunkFailure(cmd.userId(), upload.getId());
            throw new BusinessException("upload_paused", "Upload has been paused", HttpStatus.CONFLICT);
        } catch (Exception ex) {
            failUploadAfterChunkFailure(cmd.userId(), upload.getId(), "Unable to store uploaded file");
            throw new BusinessException("storage_error", "Unable to store uploaded file", HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }

    @Transactional
    public UploadTaskVM initDirectUpload(
            UUID userId,
            UUID deviceId,
            UUID parentId,
            String fileName,
            long sizeBytes,
            String mimeType
    ) {
        var normalizedFileName = normalizeFileName(fileName);
        if (normalizedFileName.isBlank()) {
            throw new BusinessException("validation_error", "File name is required", HttpStatus.BAD_REQUEST);
        }
        quotaService.checkCanUpload(userId, sizeBytes);
        fileService.validateCreateFileTarget(userId, parentId, normalizedFileName);
        var objectKey = userId + "/" + UUID.randomUUID() + "/" + normalizedFileName;
        var upload = uploadTaskRepository.save(UploadTaskEntity.create(
                userId,
                parentId,
                normalizedFileName,
                sizeBytes,
                mimeType,
                "0".repeat(64),
                objectKey
        ));
        transferTaskService.createTask(new CreateTransferTaskCmd(
                userId,
                deviceId,
                TransferDirection.UPLOAD,
                TransferTaskType.FILE,
                upload.getId(),
                normalizedFileName,
                sizeBytes
        ));
        return toVm(upload);
    }

    @Transactional
    public void reportProgress(UUID userId, UUID uploadId, long transferredBytes) {
        var upload = uploadTaskRepository.getByIdAndUserId(uploadId, userId);
        upload.reportProgress(transferredBytes);
        transferTaskService.updateProgressBySource(userId, uploadId, transferredBytes);
    }

    private String normalizeFileName(String fileName) {
        if (fileName == null) {
            return "";
        }
        var normalized = fileName.replace('\\', '/');
        var slashIndex = normalized.lastIndexOf('/');
        if (slashIndex >= 0) {
            normalized = normalized.substring(slashIndex + 1);
        }
        return normalized.trim();
    }

    public UploadTaskVM getTask(UUID userId, UUID uploadId) {
        var task = uploadTaskRepository.getByIdAndUserId(uploadId, userId);
        syncResumableProgress(userId, task);
        return toVm(task);
    }

    @Transactional
    public FileNodeVM complete(UUID userId, UUID uploadId) {
        var task = uploadTaskRepository.getByIdAndUserId(uploadId, userId);
        var tempPath = resumableUploadPath(userId, uploadId);
        if (Files.exists(tempPath)) {
            try {
                if (Files.size(tempPath) != task.getSizeBytes()) {
                    throw new BusinessException("validation_error", "Upload is not complete", HttpStatus.BAD_REQUEST);
                }
                return completeResumableUpload(userId, task, tempPath);
            } catch (BusinessException ex) {
                throw ex;
            } catch (IOException ex) {
                throw new BusinessException("storage_error", "Unable to store uploaded file", HttpStatus.INTERNAL_SERVER_ERROR);
            }
        }
        if (task.getStatus() == UploadTaskStatus.DONE) {
            throw new BusinessException("validation_error", "Upload is already completed", HttpStatus.BAD_REQUEST);
        }
        if (task.getStatus() == UploadTaskStatus.CANCELED) {
            localObjectStore.deleteIfExists(task.getObjectKey());
            throw new BusinessException("upload_canceled", "Upload has been canceled", HttpStatus.CONFLICT);
        }
        var object = storageObjectService.createObject(
                task.getObjectKey(),
                task.getSha256(),
                task.getSizeBytes(),
                task.getMimeType()
        );
        var file = fileService.createFile(new CreateFileNodeCmd(
                userId,
                task.getParentId(),
                object.getId(),
                task.getFileName(),
                task.getSizeBytes(),
                task.getMimeType(),
                task.getSha256()
        ));
        quotaService.commitUpload(userId, task.getSizeBytes());
        task.complete(Instant.now());
        transferTaskService.completeBySource(userId, uploadId);
        return file;
    }

    @Transactional
    public void pause(UUID userId, UUID uploadId) {
        uploadTaskRepository.getByIdAndUserId(uploadId, userId).pause();
        transferTaskService.pauseBySource(userId, uploadId);
    }

    @Transactional
    public void resume(UUID userId, UUID uploadId) {
        uploadTaskRepository.getByIdAndUserId(uploadId, userId).resume();
        transferTaskService.resumeBySource(userId, uploadId);
    }

    @Transactional
    public void cancel(UUID userId, UUID uploadId) {
        var task = uploadTaskRepository.getByIdAndUserId(uploadId, userId);
        var completed = task.getStatus() == UploadTaskStatus.DONE;
        task.cancel();
        try {
            Files.deleteIfExists(resumableUploadPath(userId, uploadId));
        } catch (IOException ignored) {
            // The task should still be canceled if residual local cleanup fails.
        }
        if (!completed) {
            try {
                localObjectStore.deleteIfExists(task.getObjectKey());
            } catch (RuntimeException ignored) {
                // The task record should still be removed if residual object cleanup fails.
            }
            uploadTaskRepository.delete(task);
        }
        transferTaskService.cancelBySource(userId, uploadId);
    }

    public UploadTaskVM toVm(UploadTaskEntity task) {
        return new UploadTaskVM(
                task.getId(),
                task.getFileName(),
                task.getSizeBytes(),
                task.getTransferredBytes(),
                task.getStatus().name().toLowerCase(),
                task.getCreatedAt(),
                task.getUpdatedAt(),
                task.getCompletedAt()
        );
    }

    private long appendUploadChunk(
            UUID userId,
            UUID uploadId,
            Path tempPath,
            InputStream content,
            long existingBytes,
            long sizeBytes
    ) throws IOException {
        var transferredBytes = existingBytes;
        var lastReportedBytes = existingBytes;
        try (var outputStream = Files.newOutputStream(
                tempPath,
                StandardOpenOption.CREATE,
                StandardOpenOption.APPEND
        )) {
            var buffer = new byte[64 * 1024];
            int read;
            while ((read = content.read(buffer)) >= 0) {
                if (transferredBytes + read > sizeBytes) {
                    throw new BusinessException("validation_error", "Uploaded bytes exceed task size", HttpStatus.BAD_REQUEST);
                }
                outputStream.write(buffer, 0, read);
                transferredBytes += read;
                if (transferredBytes - lastReportedBytes >= 512L * 1024L || transferredBytes >= sizeBytes) {
                    updateUploadProgress(userId, uploadId, transferredBytes);
                    lastReportedBytes = transferredBytes;
                }
            }
        }
        if (transferredBytes != lastReportedBytes) {
            updateUploadProgress(userId, uploadId, transferredBytes);
        }
        return transferredBytes;
    }

    private void updateUploadProgress(UUID userId, UUID uploadId, long transferredBytes) {
        var upload = uploadTaskRepository.getByIdAndUserId(uploadId, userId);
        upload.reportProgress(transferredBytes);
        uploadTaskRepository.saveAndFlush(upload);
        transferTaskService.updateProgressBySource(userId, uploadId, transferredBytes);
    }

    private void pauseUploadAfterChunkFailure(UUID userId, UUID uploadId) {
        var upload = uploadTaskRepository.getByIdAndUserId(uploadId, userId);
        upload.pause();
        uploadTaskRepository.saveAndFlush(upload);
        transferTaskService.pauseBySource(userId, uploadId);
    }

    private void failUploadAfterChunkFailure(UUID userId, UUID uploadId, String reason) {
        var upload = uploadTaskRepository.getByIdAndUserId(uploadId, userId);
        upload.fail();
        uploadTaskRepository.saveAndFlush(upload);
        transferTaskService.failBySource(userId, uploadId, reason);
    }

    private FileNodeVM completeResumableUploadInTransaction(UUID userId, UUID uploadId, Path tempPath) throws IOException {
        try {
            var file = transactionTemplate.execute(status -> {
                try {
                    var upload = uploadTaskRepository.getByIdAndUserId(uploadId, userId);
                    return completeResumableUpload(userId, upload, tempPath);
                } catch (IOException ex) {
                    throw new UncheckedIOException(ex);
                }
            });
            if (file == null) {
                throw new IOException("Unable to complete uploaded file");
            }
            return file;
        } catch (UncheckedIOException ex) {
            throw ex.getCause();
        }
    }

    private FileNodeVM completeResumableUpload(UUID userId, UploadTaskEntity upload, Path tempPath) throws IOException {
        String sha256;
        try {
            var digest = MessageDigest.getInstance("SHA-256");
            try (var inputStream = new DigestInputStream(Files.newInputStream(tempPath), digest)) {
                localObjectStore.save(upload.getObjectKey(), inputStream, upload.getSizeBytes(), upload.getMimeType());
            }
            sha256 = HexFormat.of().formatHex(digest.digest());
        } catch (Exception ex) {
            upload.fail();
            uploadTaskRepository.saveAndFlush(upload);
            transferTaskService.failBySource(userId, upload.getId(), "Unable to store uploaded file");
            throw new BusinessException("storage_error", "Unable to store uploaded file", HttpStatus.INTERNAL_SERVER_ERROR);
        }

        upload.markStored(sha256, upload.getMimeType());
        var object = storageObjectService.createObject(upload.getObjectKey(), sha256, upload.getSizeBytes(), upload.getMimeType());
        var file = fileService.createFile(new CreateFileNodeCmd(
                userId,
                upload.getParentId(),
                object.getId(),
                upload.getFileName(),
                upload.getSizeBytes(),
                upload.getMimeType(),
                sha256
        ));
        quotaService.commitUpload(userId, upload.getSizeBytes());
        upload.complete(Instant.now());
        uploadTaskRepository.saveAndFlush(upload);
        transferTaskService.completeBySource(userId, upload.getId());
        Files.deleteIfExists(tempPath);
        return file;
    }

    private Path resumableUploadPath(UUID userId, UUID uploadId) {
        return resumableUploadDirectory.resolve(userId.toString()).resolve(uploadId + ".part");
    }

    private void syncResumableProgress(UUID userId, UploadTaskEntity task) {
        var tempPath = resumableUploadPath(userId, task.getId());
        try {
            if (!Files.exists(tempPath)) {
                return;
            }
            var bytes = Math.min(Files.size(tempPath), task.getSizeBytes());
            if (bytes != task.getTransferredBytes()) {
                task.reportProgress(bytes);
                uploadTaskRepository.saveAndFlush(task);
                transferTaskService.updateProgressBySource(userId, task.getId(), bytes);
            }
        } catch (IOException ignored) {
            // Keep the persisted task progress if the temporary file cannot be inspected.
        }
    }
}
