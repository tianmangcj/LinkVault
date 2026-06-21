import 'dart:io';

import '../network/api_exceptions.dart';
import '../network/linkvault_api_client.dart';
import '../network/linkvault_models.dart';
import '../platform/android_downloads.dart';
import '../platform/android_uploads.dart';
import 'transfer_resume_store.dart';

class TransferResumeService {
  const TransferResumeService({
    required LinkVaultApi apiClient,
    required TransferResumeStore store,
    required void Function() onChanged,
  }) : _apiClient = apiClient,
       _store = store,
       _onChanged = onChanged;

  final LinkVaultApi _apiClient;
  final TransferResumeStore _store;
  final void Function() _onChanged;
  static final Set<String> _runningTaskIds = <String>{};

  Future<LocalTransferRecord> registerUpload({
    required String path,
    required String fileName,
    required String? parentId,
  }) async {
    final sizeBytes = await _localFileSize(path);
    final task = await _apiClient.initDirectUploadTask(
      parentId: parentId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      mimeType: null,
    );
    final transferTaskId =
        await _transferTaskIdForSource(
          sourceId: task.id,
          direction: TransferDirection.upload,
        ) ??
        task.id;
    final record = LocalTransferRecord(
      kind: LocalTransferKind.upload,
      taskId: transferTaskId,
      sourceId: task.id,
      title: fileName,
      localPath: path,
      parentId: parentId,
      totalBytes: sizeBytes,
      transferredBytes: task.transferredBytes,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    await _store.save(record);
    return record;
  }

  Future<PrepareDownloadInfo> registerDownload({
    required String fileId,
    required String savePath,
  }) async {
    await _resetDownloadTarget(savePath);
    final info = await _apiClient.prepareDownload(fileId);
    final transferTaskId =
        await _transferTaskIdForSource(
          sourceId: info.downloadTaskId,
          direction: TransferDirection.download,
        ) ??
        info.downloadTaskId;
    final record = LocalTransferRecord(
      kind: LocalTransferKind.download,
      taskId: transferTaskId,
      sourceId: info.downloadTaskId,
      title: info.fileName,
      localPath: savePath,
      fileId: info.fileId,
      totalBytes: info.sizeBytes,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    await _store.save(record);
    return info;
  }

  Future<void> discardInterruptedTransfers() async {
    final records = await _store.readAll();
    var changed = false;
    for (final record in records) {
      try {
        await _discardInterruptedTransfer(record);
        await _store.delete(record.taskId);
        await _store.delete(record.sourceId);
        changed = true;
      } catch (_) {
        // Keep the local record so the next startup can retry cleanup.
        changed = true;
      }
    }
    if (changed) {
      _onChanged();
    }
  }

  Future<void> pause(TransferTaskInfo task) async {
    if (task.direction == TransferDirection.download) {
      await _apiClient.pauseLocalDownload(task.sourceId);
    }
    await _apiClient.pauseTransferTask(task.id);
    _onChanged();
  }

  Future<void> delete(TransferTaskInfo task) async {
    await _cancelActiveTransferSource(task);
    await _apiClient.deleteTransferTask(task.id);
    await _store.delete(task.id);
    await _store.delete(task.sourceId);
    _onChanged();
  }

  Future<void> clear(
    List<TransferTaskInfo> tasks,
    TransferDirection direction,
  ) async {
    for (final task in tasks) {
      await _cancelActiveTransferSource(task);
      await _store.delete(task.id);
      await _store.delete(task.sourceId);
    }
    await _apiClient.clearTransferTasks(direction);
    _onChanged();
  }

  Future<void> _cancelActiveTransferSource(TransferTaskInfo task) async {
    if (task.direction == TransferDirection.download) {
      await _apiClient.cancelLocalDownload(task.sourceId);
      return;
    }
    try {
      await _apiClient.cancelUploadTask(task.sourceId);
    } catch (_) {
      // deleteTransferTask/clearTransferTasks will still cancel the server-side
      // source task; this call primarily interrupts a currently active client
      // upload stream before the task row is removed.
    }
  }

  Future<void> _discardInterruptedTransfer(LocalTransferRecord record) async {
    final direction = switch (record.kind) {
      LocalTransferKind.download => TransferDirection.download,
      LocalTransferKind.upload => TransferDirection.upload,
    };
    final transferTask = await _transferTaskForRecord(
      record,
      direction: direction,
    );
    if (transferTask?.status == TransferTaskStatus.done) {
      return;
    }

    switch (record.kind) {
      case LocalTransferKind.download:
        try {
          await _apiClient.cancelLocalDownload(record.sourceId);
        } catch (_) {
          // No local download may be active during startup cleanup.
        }
        Object? localDeletionError;
        try {
          await _deleteDownloadedData(record.localPath);
        } catch (error) {
          localDeletionError = error;
          // Continue canceling the server task even if the local file provider
          // refuses deletion; startup cleanup should not leave a resumable task.
        }
        await _cancelTransferRecord(
          record,
          direction: direction,
          cancelSource: _apiClient.cancelDownloadTask,
        );
        if (localDeletionError != null) {
          throw localDeletionError;
        }
      case LocalTransferKind.upload:
        try {
          await _apiClient.cancelUploadTask(record.sourceId);
        } catch (_) {
          // The upload source may have already been removed. The transfer task
          // still needs to be hidden below.
        }
        await _cancelTransferRecord(
          record,
          direction: direction,
          cancelSource: _apiClient.cancelUploadTask,
        );
    }
  }

  Future<TransferTaskInfo?> _transferTaskForRecord(
    LocalTransferRecord record, {
    required TransferDirection direction,
  }) async {
    try {
      final page = await _apiClient.transferTasks(
        direction: direction,
        page: 1,
        perPage: 100,
      );
      for (final task in page.items) {
        if (task.id == record.taskId || task.sourceId == record.sourceId) {
          return task;
        }
      }
    } catch (_) {
      // If the task cannot be inspected, treat the local record as interrupted.
    }
    return null;
  }

  Future<void> _cancelTransferRecord(
    LocalTransferRecord record, {
    required TransferDirection direction,
    required Future<void> Function(String sourceId) cancelSource,
  }) async {
    var transferTaskCanceled = false;
    try {
      await _apiClient.cancelTransferTask(record.taskId);
      transferTaskCanceled = true;
    } catch (_) {
      transferTaskCanceled = await _cancelTransferTaskBySource(
        sourceId: record.sourceId,
        direction: direction,
      );
    }
    if (!transferTaskCanceled) {
      try {
        await cancelSource(record.sourceId);
      } catch (_) {
        // Cleanup runs during startup and should not block the app if the
        // server already removed the source task.
      }
    }
  }

  Future<bool> _cancelTransferTaskBySource({
    required String sourceId,
    required TransferDirection direction,
  }) async {
    try {
      final page = await _apiClient.transferTasks(
        direction: direction,
        page: 1,
        perPage: 100,
      );
      for (final task in page.items) {
        if (task.sourceId == sourceId) {
          await _apiClient.cancelTransferTask(task.id);
          return true;
        }
      }
    } catch (_) {
      // Fall back to canceling the source task directly.
    }
    return false;
  }

  Future<void> resume(
    TransferTaskInfo task, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    if (!_runningTaskIds.add(task.id)) {
      return;
    }
    try {
      await _resumeUnlocked(task, onProgress: onProgress);
    } finally {
      _runningTaskIds.remove(task.id);
    }
  }

  Future<void> _resumeUnlocked(
    TransferTaskInfo task, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final record =
        await _store.readByTaskId(task.id) ??
        await _store.readBySourceId(task.sourceId);
    if (record == null) {
      throw const LocalFileApiException('无法继续传输，请重新选择项目');
    }
    final normalizedRecord = record.copyWith(
      taskId: task.id,
      sourceId: task.sourceId,
      title: task.title,
      totalBytes: task.totalBytes,
      transferredBytes: task.transferredBytes,
    );
    if (record.taskId != normalizedRecord.taskId ||
        record.sourceId != normalizedRecord.sourceId) {
      await _store.delete(record.taskId);
    }
    await _store.save(normalizedRecord);
    switch (normalizedRecord.kind) {
      case LocalTransferKind.download:
        await _resumeDownload(normalizedRecord, onProgress: onProgress);
      case LocalTransferKind.upload:
        await _resumeUpload(normalizedRecord, onProgress: onProgress);
    }
  }

  Future<void> complete(String taskId) async {
    await _store.delete(taskId);
    final record = await _store.readBySourceId(taskId);
    if (record != null) {
      await _store.delete(record.taskId);
    }
  }

  Future<void> _resumeDownload(
    LocalTransferRecord record, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final offset = await _downloadedBytes(record.localPath, record.totalBytes);
    final info = await _apiClient.resumeDownload(record.sourceId);
    await _store.save(
      record.copyWith(
        fileId: info.fileId,
        title: info.fileName,
        totalBytes: info.sizeBytes,
        transferredBytes: offset,
      ),
    );
    try {
      await _apiClient.downloadPreparedFile(
        info: info,
        savePath: record.localPath,
        offset: offset,
        onProgress: (progress) {
          _onChanged();
          onProgress?.call(progress);
        },
      );
      await _store.delete(record.taskId);
      await _store.delete(record.sourceId);
      _onChanged();
    } catch (_) {
      _onChanged();
      rethrow;
    }
  }

  Future<void> _resumeUpload(
    LocalTransferRecord record, {
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    try {
      final task = await _apiClient.uploadTask(record.sourceId);
      await _apiClient.resumeTransferTask(record.taskId);
      await _apiClient.uploadPreparedFile(
        uploadTaskId: record.sourceId,
        path: record.localPath,
        fileName: record.title,
        offset: task.transferredBytes,
        onProgress: (progress) {
          _onChanged();
          onProgress?.call(progress);
        },
      );
      await _store.delete(record.taskId);
      await _store.delete(record.sourceId);
      _onChanged();
    } catch (_) {
      _onChanged();
      rethrow;
    }
  }

  Future<int> _downloadedBytes(String path, int totalBytes) async {
    if (AndroidDownloads.isTargetPath(path)) {
      final size = await AndroidDownloads.size(path);
      return size.clamp(0, totalBytes).toInt();
    }
    final file = File(path);
    if (!await file.exists()) {
      return 0;
    }
    final size = await file.length();
    return size.clamp(0, totalBytes).toInt();
  }

  Future<String?> _transferTaskIdForSource({
    required String sourceId,
    required TransferDirection direction,
  }) async {
    try {
      final page = await _apiClient.transferTasks(
        direction: direction,
        page: 1,
        perPage: 100,
      );
      for (final task in page.items) {
        if (task.sourceId == sourceId) {
          return task.id;
        }
      }
    } catch (_) {
      // The task-center resume path can normalize older local records later.
    }
    return null;
  }

  Future<void> _resetDownloadTarget(String path) async {
    await _deleteDownloadedData(path);
  }

  Future<void> _deleteDownloadedData(String path) async {
    if (AndroidDownloads.isTargetPath(path)) {
      await AndroidDownloads.deleteDownload(path);
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<int> _localFileSize(String path) async {
    if (AndroidUploads.isTargetPath(path)) {
      final target = AndroidUploads.parseTargetPath(path);
      if (target.sizeBytes > 0) {
        return target.sizeBytes;
      }
      throw const LocalFileApiException('无法读取文件大小，请重新选择后再试');
    }
    return File(path).length();
  }
}
