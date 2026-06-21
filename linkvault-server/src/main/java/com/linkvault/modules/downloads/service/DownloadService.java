package com.linkvault.modules.downloads.service;

import com.linkvault.common.exception.BusinessException;
import com.linkvault.modules.downloads.domain.DownloadTaskEntity;
import com.linkvault.modules.downloads.domain.DownloadTaskStatus;
import com.linkvault.modules.downloads.dto.BatchDownloadStreamResult;
import com.linkvault.modules.downloads.dto.DownloadStreamResult;
import com.linkvault.modules.downloads.dto.PrepareDownloadCmd;
import com.linkvault.modules.downloads.dto.PrepareDownloadResult;
import com.linkvault.modules.downloads.repository.DownloadTaskRepository;
import com.linkvault.modules.files.domain.FileNodeEntity;
import com.linkvault.modules.files.domain.FileNodeType;
import com.linkvault.modules.files.service.FileService;
import com.linkvault.modules.storage.service.LocalObjectStore;
import com.linkvault.modules.storage.service.ObjectStorageClient;
import com.linkvault.modules.storage.service.StorageObjectService;
import com.linkvault.modules.transfers.domain.TransferDirection;
import com.linkvault.modules.transfers.domain.TransferTaskType;
import com.linkvault.modules.transfers.dto.CreateTransferTaskCmd;
import com.linkvault.modules.transfers.service.TransferTaskService;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.Duration;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

@Service
public class DownloadService {
    private final DownloadTaskRepository downloadTaskRepository;
    private final FileService fileService;
    private final StorageObjectService storageObjectService;
    private final ObjectStorageClient objectStorageClient;
    private final LocalObjectStore localObjectStore;
    private final TransferTaskService transferTaskService;
    private final TransactionTemplate transactionTemplate;

    public DownloadService(
            DownloadTaskRepository downloadTaskRepository,
            FileService fileService,
            StorageObjectService storageObjectService,
            ObjectStorageClient objectStorageClient,
            LocalObjectStore localObjectStore,
            TransferTaskService transferTaskService,
            TransactionTemplate transactionTemplate
    ) {
        this.downloadTaskRepository = downloadTaskRepository;
        this.fileService = fileService;
        this.storageObjectService = storageObjectService;
        this.objectStorageClient = objectStorageClient;
        this.localObjectStore = localObjectStore;
        this.transferTaskService = transferTaskService;
        this.transactionTemplate = transactionTemplate;
    }

    @Transactional
    public PrepareDownloadResult prepareDownload(PrepareDownloadCmd cmd) {
        var file = fileService.getActiveFileEntity(cmd.userId(), cmd.fileId());
        if (file.getType() != FileNodeType.FILE || file.getStorageObjectId() == null) {
            throw new BusinessException("validation_error", "Only files can be downloaded", HttpStatus.BAD_REQUEST);
        }
        var object = storageObjectService.get(file.getStorageObjectId());
        var task = downloadTaskRepository.save(DownloadTaskEntity.create(
                cmd.userId(),
                cmd.fileId(),
                file.getName(),
                file.getSizeBytes()
        ));
        transferTaskService.createTask(new CreateTransferTaskCmd(
                cmd.userId(),
                cmd.deviceId(),
                TransferDirection.DOWNLOAD,
                TransferTaskType.FILE,
                task.getId(),
                file.getName(),
                file.getSizeBytes()
        ));
        var url = objectStorageClient.presignGet(object.getObjectKey(), Duration.ofMinutes(30));
        return new PrepareDownloadResult(
                task.getId(),
                file.getId(),
                file.getName(),
                file.getSizeBytes(),
                file.getMimeType(),
                url
        );
    }

    @Transactional
    public PrepareDownloadResult resumeDownload(UUID userId, UUID downloadTaskId) {
        var task = downloadTaskRepository.getByIdAndUserId(downloadTaskId, userId);
        if (task.getStatus() == DownloadTaskStatus.CANCELED) {
            throw new BusinessException("download_canceled", "Download has been canceled", HttpStatus.CONFLICT);
        }
        if (task.getStatus() == DownloadTaskStatus.DONE) {
            throw new BusinessException("download_completed", "Download is already completed", HttpStatus.CONFLICT);
        }
        var file = fileService.getActiveFileEntity(userId, task.getFileId());
        if (file.getType() != FileNodeType.FILE || file.getStorageObjectId() == null) {
            throw new BusinessException("validation_error", "Only files can be downloaded", HttpStatus.BAD_REQUEST);
        }
        var object = storageObjectService.get(file.getStorageObjectId());
        task.resume();
        transferTaskService.resumeBySource(userId, downloadTaskId);
        var url = objectStorageClient.presignGet(object.getObjectKey(), Duration.ofMinutes(30));
        return new PrepareDownloadResult(
                task.getId(),
                file.getId(),
                file.getName(),
                file.getSizeBytes(),
                file.getMimeType(),
                url
        );
    }

    @Transactional(readOnly = true)
    public DownloadStreamResult streamFile(UUID userId, UUID fileId) {
        return streamFile(userId, fileId, 0);
    }

    @Transactional(readOnly = true)
    public DownloadStreamResult streamFile(UUID userId, UUID fileId, long offset) {
        var file = fileService.getActiveFileEntity(userId, fileId);
        if (file.getType() != FileNodeType.FILE || file.getStorageObjectId() == null) {
            throw new BusinessException("validation_error", "Only files can be downloaded", HttpStatus.BAD_REQUEST);
        }
        var safeOffset = Math.max(0, Math.min(offset, file.getSizeBytes()));
        var object = storageObjectService.get(file.getStorageObjectId());
        StreamingResponseBody body = outputStream -> {
            try (var inputStream = localObjectStore.open(object.getObjectKey())) {
                skipFully(inputStream, safeOffset);
                inputStream.transferTo(outputStream);
            }
        };
        return new DownloadStreamResult(file.getName(), file.getSizeBytes(), safeOffset, file.getMimeType(), body);
    }

    @Transactional
    public BatchDownloadStreamResult streamBatch(UUID userId, UUID deviceId, List<UUID> fileIds) {
        FileService.validateBatchFileIds(fileIds);
        var roots = fileIds.stream()
                .map(fileId -> fileService.getActiveFileEntity(userId, fileId))
                .toList();
        var entries = new ArrayList<BatchZipEntrySource>();
        var usedRootPaths = new HashSet<String>();
        for (var root : roots) {
            collectZipEntries(userId, root, uniqueRootPath(root.getName(), usedRootPaths), entries);
        }

        var totalBytes = entries.stream()
                .filter(entry -> !entry.directory())
                .mapToLong(BatchZipEntrySource::sizeBytes)
                .sum();
        var archiveName = archiveName(roots);
        var task = downloadTaskRepository.save(DownloadTaskEntity.create(
                userId,
                roots.getFirst().getId(),
                archiveName,
                totalBytes
        ));
        transferTaskService.createTask(new CreateTransferTaskCmd(
                userId,
                deviceId,
                TransferDirection.DOWNLOAD,
                roots.size() == 1 && roots.getFirst().getType() == FileNodeType.FILE
                        ? TransferTaskType.FILE
                        : TransferTaskType.FOLDER,
                task.getId(),
                archiveName,
                totalBytes
        ));

        return new BatchDownloadStreamResult(
                archiveName,
                outputStream -> writeZip(userId, task.getId(), entries, outputStream)
        );
    }

    @Transactional
    public void reportProgress(UUID userId, UUID downloadTaskId, long downloadedBytes) {
        var task = downloadTaskRepository.getByIdAndUserId(downloadTaskId, userId);
        task.reportProgress(downloadedBytes);
        transferTaskService.updateProgressBySource(userId, downloadTaskId, downloadedBytes);
    }

    @Transactional
    public void completeDownload(UUID userId, UUID downloadTaskId) {
        var task = downloadTaskRepository.getByIdAndUserId(downloadTaskId, userId);
        if (task.getStatus() == DownloadTaskStatus.CANCELED) {
            throw new BusinessException("download_canceled", "Download has been canceled", HttpStatus.CONFLICT);
        }
        task.complete();
        transferTaskService.completeBySource(userId, downloadTaskId);
    }

    @Transactional
    public void cancelDownload(UUID userId, UUID downloadTaskId) {
        downloadTaskRepository.getByIdAndUserId(downloadTaskId, userId).cancel();
        transferTaskService.cancelBySource(userId, downloadTaskId);
    }

    @Transactional
    public void pauseDownload(UUID userId, UUID downloadTaskId) {
        downloadTaskRepository.getByIdAndUserId(downloadTaskId, userId).pause();
        transferTaskService.pauseBySource(userId, downloadTaskId);
    }

    private void collectZipEntries(
            UUID userId,
            FileNodeEntity node,
            String path,
            List<BatchZipEntrySource> entries
    ) {
        if (node.getType() == FileNodeType.FOLDER) {
            entries.add(BatchZipEntrySource.directory(ensureDirectoryPath(path)));
            fileService.activeChildren(userId, node.getId())
                    .forEach(child -> collectZipEntries(userId, child, path + "/" + child.getName(), entries));
            return;
        }
        if (node.getStorageObjectId() == null) {
            throw new BusinessException("validation_error", "Only stored files can be downloaded", HttpStatus.BAD_REQUEST);
        }
        var object = storageObjectService.get(node.getStorageObjectId());
        entries.add(BatchZipEntrySource.file(path, object.getObjectKey(), node.getSizeBytes()));
    }

    private void writeZip(
            UUID userId,
            UUID downloadTaskId,
            List<BatchZipEntrySource> entries,
            java.io.OutputStream outputStream
    ) throws IOException {
        var progress = new BatchTransferProgress(userId, downloadTaskId);
        try (var zip = new ZipOutputStream(outputStream, StandardCharsets.UTF_8)) {
            for (var entry : entries) {
                zip.putNextEntry(new ZipEntry(entry.path()));
                if (!entry.directory()) {
                    writeObjectToZip(entry, zip, progress);
                }
                zip.closeEntry();
            }
            zip.finish();
            completeStreamingDownload(userId, downloadTaskId);
        } catch (IOException | RuntimeException exception) {
            cancelStreamingDownload(userId, downloadTaskId);
            throw exception;
        }
    }

    private void writeObjectToZip(
            BatchZipEntrySource entry,
            ZipOutputStream zip,
            BatchTransferProgress progress
    ) throws IOException {
        var buffer = new byte[64 * 1024];
        try (var inputStream = localObjectStore.open(entry.objectKey())) {
            int read;
            while ((read = inputStream.read(buffer)) >= 0) {
                zip.write(buffer, 0, read);
                progress.add(read);
            }
        }
    }

    private void reportStreamingDownloadProgress(UUID userId, UUID downloadTaskId, long bytes) {
        transactionTemplate.executeWithoutResult(status ->
                downloadTaskRepository.getByIdAndUserId(downloadTaskId, userId).reportProgress(bytes)
        );
        transferTaskService.updateProgressBySource(userId, downloadTaskId, bytes);
    }

    private void completeStreamingDownload(UUID userId, UUID downloadTaskId) {
        transactionTemplate.executeWithoutResult(status ->
                downloadTaskRepository.getByIdAndUserId(downloadTaskId, userId).complete()
        );
        transferTaskService.completeBySource(userId, downloadTaskId);
    }

    private void cancelStreamingDownload(UUID userId, UUID downloadTaskId) {
        transactionTemplate.executeWithoutResult(status ->
                downloadTaskRepository.getByIdAndUserId(downloadTaskId, userId).cancel()
        );
        transferTaskService.cancelBySource(userId, downloadTaskId);
    }

    private void skipFully(java.io.InputStream inputStream, long bytes) throws IOException {
        var remaining = bytes;
        while (remaining > 0) {
            var skipped = inputStream.skip(remaining);
            if (skipped <= 0) {
                if (inputStream.read() < 0) {
                    return;
                }
                skipped = 1;
            }
            remaining -= skipped;
        }
    }

    private String archiveName(List<FileNodeEntity> roots) {
        if (roots.size() == 1) {
            return roots.getFirst().getName() + ".zip";
        }
        return "linkvault-download-" + Instant.now().toEpochMilli() + ".zip";
    }

    private String uniqueRootPath(String name, HashSet<String> usedPaths) {
        var candidate = name;
        var suffix = 2;
        while (!usedPaths.add(candidate)) {
            candidate = name + " (" + suffix + ")";
            suffix++;
        }
        return candidate;
    }

    private String ensureDirectoryPath(String path) {
        return path.endsWith("/") ? path : path + "/";
    }

    private record BatchZipEntrySource(
            String path,
            String objectKey,
            long sizeBytes,
            boolean directory
    ) {

        static BatchZipEntrySource directory(String path) {
            return new BatchZipEntrySource(path, null, 0, true);
        }

        static BatchZipEntrySource file(String path, String objectKey, long sizeBytes) {
            return new BatchZipEntrySource(path, objectKey, sizeBytes, false);
        }
    }

    private class BatchTransferProgress {
        private static final long REPORT_EVERY_BYTES = 512L * 1024L;

        private final UUID userId;
        private final UUID downloadTaskId;
        private long transferredBytes;
        private long lastReportedBytes;

        private BatchTransferProgress(UUID userId, UUID downloadTaskId) {
            this.userId = userId;
            this.downloadTaskId = downloadTaskId;
        }

        private void add(long bytes) {
            transferredBytes += bytes;
            if (transferredBytes - lastReportedBytes >= REPORT_EVERY_BYTES) {
                reportStreamingDownloadProgress(userId, downloadTaskId, transferredBytes);
                lastReportedBytes = transferredBytes;
            }
        }
    }

}
