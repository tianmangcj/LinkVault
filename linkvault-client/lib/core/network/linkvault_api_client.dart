import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../platform/android_downloads.dart';
import '../platform/android_transfer_priority.dart';
import '../platform/android_uploads.dart';
import '../platform/current_device.dart';
import 'api_exceptions.dart';
import 'linkvault_models.dart';
import 'token_storage.dart';

abstract interface class LinkVaultApi {
  Future<CaptchaChallenge> captcha();

  Future<CaptchaVerification> checkCaptcha({
    required String token,
    required String pointJson,
  });

  Future<AuthSession> login({
    required String account,
    required String password,
    required String captchaVerification,
  });

  Future<AuthSession> register({
    required String username,
    required String password,
    required String confirmPassword,
    required String captchaVerification,
  });

  Future<UserProfile> me();

  Future<UserProfile> updateUsername(String username);

  Future<UserProfile> updateAvatar(String avatarImageData);

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  });

  Future<void> deleteAccount();

  Future<QuotaInfo> quota();

  Future<List<DeviceInfo>> devices();

  Future<DeviceInfo> reportCurrentDevice();

  Future<void> revokeDevice(String deviceId);

  Future<PageResult<FileNode>> files({
    FileNodeType? type,
    String? parentId,
    int page = 1,
    int perPage = 50,
  });

  Future<PageResult<FileNode>> searchFiles({
    required String query,
    required FileSearchScope scope,
    String? parentId,
    int page = 1,
    int perPage = 50,
  });

  Future<FileNode> createFolder({String? parentId, required String name});

  Future<FileNode> uploadFile({
    required String path,
    required String fileName,
    String? parentId,
    void Function(DownloadProgress progress)? onProgress,
  });

  Future<UploadTaskInfo> initDirectUploadTask({
    required String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
  });

  Future<FileNode> uploadPreparedFile({
    required String uploadTaskId,
    required String path,
    required String fileName,
    int offset = 0,
    void Function(DownloadProgress progress)? onProgress,
  });

  Future<UploadTaskInfo> uploadTask(String uploadTaskId);

  Future<FileNode> renameFile(String fileId, String name);

  Future<FileNode> moveFile(String fileId, String? parentId);

  Future<FileNode> copyFile(String fileId, String? parentId);

  Future<void> moveToRecycleBin(String fileId);

  Future<BatchFileActionResult> moveFilesBatch({
    required List<String> fileIds,
    String? parentId,
  });

  Future<BatchFileActionResult> copyFilesBatch({
    required List<String> fileIds,
    String? parentId,
  });

  Future<BatchFileActionResult> moveToRecycleBinBatch(List<String> fileIds);

  Future<PageResult<FileNode>> recycleBin({int page = 1, int perPage = 50});

  Future<FileNode> restoreFile(
    String fileId, {
    bool useOriginalPath = true,
    String? parentId,
  });

  Future<void> purgeFile(String fileId);

  Future<void> emptyRecycleBin();

  Future<PageResult<TransferTaskInfo>> transferTasks({
    required TransferDirection direction,
    int page = 1,
    int perPage = 50,
  });

  Future<void> pauseTransferTask(String taskId);

  Future<void> resumeTransferTask(String taskId);

  Future<void> pauseAllTransferTasks();

  Future<void> resumeAllTransferTasks();

  Future<void> cancelTransferTask(String taskId);

  Future<void> deleteTransferTask(String taskId);

  Future<void> clearTransferTasks(TransferDirection direction);

  Future<void> cancelLocalDownload(String downloadTaskId);

  Future<void> pauseLocalDownload(String downloadTaskId);

  Future<void> cancelDownloadTask(String downloadTaskId);

  Future<void> cancelUploadTask(String uploadTaskId);

  Future<PrepareDownloadInfo> prepareDownload(String fileId);

  Future<PrepareDownloadInfo> resumeDownload(String downloadTaskId);

  Future<PrepareDownloadInfo> downloadFile({
    required String fileId,
    required String savePath,
    void Function(DownloadProgress progress)? onProgress,
  });

  Future<PrepareDownloadInfo> downloadPreparedFile({
    required PrepareDownloadInfo info,
    required String savePath,
    int offset = 0,
    void Function(DownloadProgress progress)? onProgress,
  });

  Future<void> downloadFilesBatch({
    required List<String> fileIds,
    required String savePath,
    int totalBytes = 0,
    void Function(DownloadProgress progress)? onProgress,
  });

  Future<void> logout();

  void close();
}

class _ActiveDownload {
  const _ActiveDownload({required this.savePath, required this.client});

  final String savePath;
  final http.Client client;
}

class _UploadHttpResponse {
  const _UploadHttpResponse({required this.response});

  final http.Response response;
}

class _PageRequestPriorityGate {
  final Set<Object> _activeRequests = <Object>{};
  final List<Completer<void>> _transferWaiters = <Completer<void>>[];

  bool get _isEnabled => AndroidTransferPriority.isSupported;

  Future<T> run<T>(Future<T> Function() action) async {
    if (!_isEnabled) {
      return action();
    }

    final token = Object();
    final shouldNotifyNative = _activeRequests.isEmpty;
    _activeRequests.add(token);
    if (shouldNotifyNative) {
      await _setNativePriorityActive(true);
    }

    try {
      return await action();
    } finally {
      _activeRequests.remove(token);
      if (_activeRequests.isEmpty) {
        await _setNativePriorityActive(false);
        _releaseTransferWaiters();
      }
    }
  }

  Future<void> waitForPageRequests() {
    if (!_isEnabled || _activeRequests.isEmpty) {
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _transferWaiters.add(waiter);
    return waiter.future;
  }

  Future<void> _setNativePriorityActive(bool active) async {
    try {
      await AndroidTransferPriority.setForegroundRequestActive(active);
    } catch (_) {
      if (!active) {
        _releaseTransferWaiters();
      }
    }
  }

  void _releaseTransferWaiters() {
    final waiters = List<Completer<void>>.of(_transferWaiters);
    _transferWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }
}

class LinkVaultApiClient implements LinkVaultApi {
  LinkVaultApiClient({
    required Uri baseUrl,
    required TokenStorage tokenStorage,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 3),
  }) : _baseUrl = baseUrl,
       _tokenStorage = tokenStorage,
       _httpClient = httpClient ?? _createHttpClient(timeout),
       _timeout = timeout;

  final Uri _baseUrl;
  final TokenStorage _tokenStorage;
  final http.Client _httpClient;
  final Duration _timeout;
  final Map<String, String> _activeNativeDownloadPaths = {};
  static const int _androidNativeDownloadMaxRetries = 3;
  static const Duration _androidNativeDownloadRetryBaseDelay = Duration(
    seconds: 1,
  );
  final Map<String, _ActiveDownload> _activeDownloads = {};
  final Map<String, http.Client> _activeUploads = {};
  final Set<String> _serverManagedDownloadCancellations = {};
  final Set<String> _localDownloadPauses = {};
  final _PageRequestPriorityGate _pageRequestPriorityGate =
      _PageRequestPriorityGate();

  static http.Client _createHttpClient(Duration timeout) {
    return IOClient(HttpClient()..connectionTimeout = timeout);
  }

  @override
  Future<CaptchaChallenge> captcha() {
    return _request<CaptchaChallenge>(
      'GET',
      '/auth/captcha',
      authenticated: false,
      parse: CaptchaChallenge.fromJson,
    );
  }

  @override
  Future<CaptchaVerification> checkCaptcha({
    required String token,
    required String pointJson,
  }) {
    return _request<CaptchaVerification>(
      'POST',
      '/auth/captcha/check',
      authenticated: false,
      body: {'token': token, 'pointJson': pointJson},
      parse: CaptchaVerification.fromJson,
    );
  }

  @override
  Future<AuthSession> login({
    required String account,
    required String password,
    required String captchaVerification,
  }) async {
    final deviceMetadata = await _deviceMetadata();
    final session = await _request<AuthSession>(
      'POST',
      '/auth/login',
      authenticated: false,
      body: {
        'account': account,
        'password': password,
        'captchaVerification': captchaVerification,
        ...deviceMetadata,
      },
      parse: AuthSession.fromJson,
    );
    await _saveSession(session);
    return session;
  }

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    required String confirmPassword,
    required String captchaVerification,
  }) async {
    final deviceMetadata = await _deviceMetadata();
    final session = await _request<AuthSession>(
      'POST',
      '/auth/register',
      authenticated: false,
      body: {
        'username': username,
        'password': password,
        'confirmPassword': confirmPassword,
        'captchaVerification': captchaVerification,
        ...deviceMetadata,
      },
      parse: AuthSession.fromJson,
    );
    await _saveSession(session);
    return session;
  }

  @override
  Future<UserProfile> me() {
    return _request<UserProfile>(
      'GET',
      '/users/me',
      parse: UserProfile.fromJson,
    );
  }

  @override
  Future<UserProfile> updateUsername(String username) {
    return _request<UserProfile>(
      'PATCH',
      '/users/me/username',
      body: {'username': username},
      parse: UserProfile.fromJson,
    );
  }

  @override
  Future<UserProfile> updateAvatar(String avatarImageData) {
    return _request<UserProfile>(
      'PATCH',
      '/users/me/avatar',
      body: {'avatarImageData': avatarImageData},
      parse: UserProfile.fromJson,
    );
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    return _requestVoid(
      'PATCH',
      '/users/me/password',
      body: {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
        'confirmPassword': confirmPassword,
      },
    );
  }

  @override
  Future<void> deleteAccount() async {
    await _requestVoid('DELETE', '/users/me');
    await _tokenStorage.clear();
  }

  @override
  Future<QuotaInfo> quota() {
    return _request<QuotaInfo>(
      'GET',
      '/users/me/quota',
      parse: QuotaInfo.fromJson,
    );
  }

  @override
  Future<List<DeviceInfo>> devices() {
    return _requestList<DeviceInfo>(
      'GET',
      '/devices',
      parse: DeviceInfo.fromJson,
    );
  }

  @override
  Future<DeviceInfo> reportCurrentDevice() async {
    return _request<DeviceInfo>(
      'POST',
      '/devices/current',
      body: await _deviceMetadata(),
      parse: DeviceInfo.fromJson,
    );
  }

  @override
  Future<void> revokeDevice(String deviceId) {
    return _requestVoid('DELETE', '/devices/$deviceId');
  }

  @override
  Future<PageResult<FileNode>> files({
    FileNodeType? type,
    String? parentId,
    int page = 1,
    int perPage = 50,
  }) {
    return _requestPage<FileNode>(
      'GET',
      '/files',
      query: {
        if (type != null) 'type': type.queryValue,
        if (parentId != null) 'parentId': parentId,
        'page': page.toString(),
        'perPage': perPage.toString(),
      },
      parse: FileNode.fromJson,
    );
  }

  @override
  Future<PageResult<FileNode>> searchFiles({
    required String query,
    required FileSearchScope scope,
    String? parentId,
    int page = 1,
    int perPage = 50,
  }) {
    return _requestPage<FileNode>(
      'GET',
      '/files/search',
      query: {
        'q': query,
        'scope': scope.queryValue,
        if (parentId != null) 'parentId': parentId,
        'page': '$page',
        'perPage': '$perPage',
      },
      parse: FileNode.fromJson,
    );
  }

  @override
  Future<FileNode> createFolder({String? parentId, required String name}) {
    return _request<FileNode>(
      'POST',
      '/files/folders',
      body: {'parentId': parentId, 'name': name},
      parse: FileNode.fromJson,
    );
  }

  @override
  Future<FileNode> uploadFile({
    required String path,
    required String fileName,
    String? parentId,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final sizeBytes = await _localUploadSize(path);
    final task = await initDirectUploadTask(
      parentId: parentId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      mimeType: null,
    );
    return uploadPreparedFile(
      uploadTaskId: task.id,
      path: path,
      fileName: fileName,
      onProgress: onProgress,
    );
  }

  @override
  Future<UploadTaskInfo> initDirectUploadTask({
    required String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
  }) async {
    final json = await _sendJson(
      'POST',
      '/uploads/direct/init',
      query: {if (parentId != null) 'parentId': parentId},
      body: {
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        if (mimeType != null) 'mimeType': mimeType,
      },
    );
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const JsonApiException('服务端响应缺少 data 对象');
    }
    return UploadTaskInfo.fromJson(data);
  }

  @override
  Future<FileNode> uploadPreparedFile({
    required String uploadTaskId,
    required String path,
    required String fileName,
    int offset = 0,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final sizeBytes = await _localUploadSize(path);
    try {
      final androidUploadTarget = AndroidUploads.isTargetPath(path)
          ? AndroidUploads.parseTargetPath(path)
          : null;
      final file = androidUploadTarget == null ? File(path) : null;
      final task = await uploadTask(uploadTaskId);
      final startOffset = offset > 0
          ? offset.clamp(0, sizeBytes).toInt()
          : task.transferredBytes.clamp(0, sizeBytes).toInt();
      final token = await _accessToken();
      final uploadUri = _uri('/uploads/direct/chunk', {
        'uploadId': uploadTaskId,
        'offset': startOffset.toString(),
        'complete': 'true',
      });
      final reportTimer = Stopwatch()..start();
      var lastReportedBytes = startOffset;
      void handleProgress(int uploadedBytes) {
        final totalUploadedBytes = (startOffset + uploadedBytes)
            .clamp(0, sizeBytes)
            .toInt();
        _notifyDownloadProgress(
          onProgress,
          DownloadProgress(
            downloadedBytes: totalUploadedBytes,
            totalBytes: sizeBytes,
          ),
        );
        if (_shouldReportDownloadProgress(
          downloadedBytes: totalUploadedBytes,
          lastReportedBytes: lastReportedBytes,
          elapsed: reportTimer.elapsed,
          totalBytes: sizeBytes,
        )) {
          lastReportedBytes = totalUploadedBytes;
          reportTimer
            ..reset()
            ..start();
        }
      }
      final response = androidUploadTarget != null
          ? await _sendAndroidUpload(
              uploadTaskId: uploadTaskId,
              path: path,
              url: uploadUri,
              token: token,
              fileName: fileName,
              offset: startOffset,
              onProgress: handleProgress,
            )
          : await _sendDartUpload(
              uploadTaskId: uploadTaskId,
              file: file!,
              url: uploadUri,
              token: token,
              fileName: fileName,
              sizeBytes: sizeBytes,
              offset: startOffset,
              onProgress: handleProgress,
            );
      final json = _decodeEnvelope(response.response);
      final data = json['data'];
      if (data is! Map<String, dynamic>) {
        throw const JsonApiException('服务端响应缺少 data 对象');
      }
      final node = FileNode.fromJson(data);
      return node;
    } catch (error) {
      final apiError = normalizeApiError(error);
      try {
        await _pauseUpload(uploadTaskId);
      } catch (_) {
        // Keep the original upload failure as the user-facing error.
      }
      throw apiError;
    }
  }

  @override
  Future<UploadTaskInfo> uploadTask(String uploadTaskId) {
    return _request<UploadTaskInfo>(
      'GET',
      '/uploads/$uploadTaskId',
      parse: UploadTaskInfo.fromJson,
    );
  }

  Future<_UploadHttpResponse> _sendDartUpload({
    required String uploadTaskId,
    required File file,
    required Uri url,
    required String token,
    required String fileName,
    required int sizeBytes,
    int offset = 0,
    void Function(int uploadedBytes)? onProgress,
  }) async {
    final safeOffset = offset.clamp(0, sizeBytes).toInt();
    final remainingBytes = sizeBytes - safeOffset;
    final uploadClient = _createHttpClient(_timeout);
    _activeUploads[uploadTaskId] = uploadClient;
    final request = http.StreamedRequest('POST', url);
    request.headers['Accept'] = 'application/json';
    request.headers['Content-Type'] = 'application/octet-stream';
    request.headers['Authorization'] = 'Bearer $token';
    request.contentLength = remainingBytes;
    await _pageRequestPriorityGate.waitForPageRequests();
    final responseFuture = uploadClient
        .send(request)
        .timeout(const Duration(minutes: 30));
    try {
      try {
        await request.sink.addStream(
          _progressStream(
            file.openRead(safeOffset),
            onProgress,
            waitForPageRequests: _pageRequestPriorityGate.waitForPageRequests,
          ),
        );
        await request.sink.close();
      } catch (_) {
        await request.sink.close();
        rethrow;
      }
      final streamedResponse = await responseFuture;
      return _UploadHttpResponse(
        response: await http.Response.fromStream(streamedResponse),
      );
    } finally {
      _activeUploads.remove(uploadTaskId);
      uploadClient.close();
    }
  }

  Future<_UploadHttpResponse> _sendAndroidUpload({
    required String uploadTaskId,
    required String path,
    required Uri url,
    required String token,
    required String fileName,
    int offset = 0,
    void Function(int uploadedBytes)? onProgress,
  }) async {
    await _pageRequestPriorityGate.waitForPageRequests();
    final response = await AndroidUploads.uploadFile(
      path: path,
      url: url,
      uploadSessionId: uploadTaskId,
      fileName: fileName,
      offset: offset,
      onProgress: onProgress,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _UploadHttpResponse(
      response: http.Response.bytes(
        utf8.encode(response.body),
        response.statusCode,
      ),
    );
  }

  Future<int> _localUploadSize(String path) async {
    final androidUploadTarget = AndroidUploads.isTargetPath(path)
        ? AndroidUploads.parseTargetPath(path)
        : null;
    if (androidUploadTarget != null) {
      final sizeBytes = androidUploadTarget.sizeBytes;
      if (sizeBytes <= 0) {
        throw const LocalFileApiException('无法读取文件大小，请重新选择后再试');
      }
      return sizeBytes;
    }
    return File(path).length();
  }

  @override
  Future<FileNode> renameFile(String fileId, String name) {
    return _request<FileNode>(
      'PATCH',
      '/files/$fileId/rename',
      body: {'name': name},
      parse: FileNode.fromJson,
    );
  }

  @override
  Future<FileNode> moveFile(String fileId, String? parentId) {
    return _request<FileNode>(
      'PATCH',
      '/files/$fileId/move',
      body: {'parentId': parentId},
      parse: FileNode.fromJson,
    );
  }

  @override
  Future<FileNode> copyFile(String fileId, String? parentId) {
    return _request<FileNode>(
      'POST',
      '/files/$fileId/copy',
      body: {'parentId': parentId},
      parse: FileNode.fromJson,
    );
  }

  @override
  Future<void> moveToRecycleBin(String fileId) {
    return _requestVoid('DELETE', '/files/$fileId');
  }

  @override
  Future<BatchFileActionResult> moveFilesBatch({
    required List<String> fileIds,
    String? parentId,
  }) {
    return _request<BatchFileActionResult>(
      'PATCH',
      '/files/batch-move',
      body: {'fileIds': fileIds, 'parentId': parentId},
      parse: BatchFileActionResult.fromJson,
    );
  }

  @override
  Future<BatchFileActionResult> copyFilesBatch({
    required List<String> fileIds,
    String? parentId,
  }) {
    return _request<BatchFileActionResult>(
      'POST',
      '/files/batch-copy',
      body: {'fileIds': fileIds, 'parentId': parentId},
      parse: BatchFileActionResult.fromJson,
    );
  }

  @override
  Future<BatchFileActionResult> moveToRecycleBinBatch(List<String> fileIds) {
    return _request<BatchFileActionResult>(
      'POST',
      '/files/batch-recycle',
      body: {'fileIds': fileIds},
      parse: BatchFileActionResult.fromJson,
    );
  }

  @override
  Future<PageResult<FileNode>> recycleBin({int page = 1, int perPage = 50}) {
    return _requestPage<FileNode>(
      'GET',
      '/recycle-bin',
      query: {'page': '$page', 'perPage': '$perPage'},
      parse: FileNode.fromJson,
    );
  }

  @override
  Future<FileNode> restoreFile(
    String fileId, {
    bool useOriginalPath = true,
    String? parentId,
  }) {
    return _request<FileNode>(
      'POST',
      '/recycle-bin/$fileId/restore',
      body: {'useOriginalPath': useOriginalPath, 'parentId': parentId},
      parse: FileNode.fromJson,
    );
  }

  @override
  Future<void> purgeFile(String fileId) {
    return _requestVoid('DELETE', '/recycle-bin/$fileId');
  }

  @override
  Future<void> emptyRecycleBin() {
    return _requestVoid('DELETE', '/recycle-bin');
  }

  @override
  Future<PageResult<TransferTaskInfo>> transferTasks({
    required TransferDirection direction,
    int page = 1,
    int perPage = 50,
  }) async {
    final listClient = _createHttpClient(_timeout);
    try {
      return await _requestPage<TransferTaskInfo>(
        'GET',
        '/transfer-tasks',
        query: {
          'direction': direction.queryValue,
          'page': '$page',
          'perPage': '$perPage',
        },
        parse: TransferTaskInfo.fromJson,
        client: listClient,
      );
    } finally {
      listClient.close();
    }
  }

  @override
  Future<void> pauseTransferTask(String taskId) {
    return _requestVoid('POST', '/transfer-tasks/$taskId/pause');
  }

  @override
  Future<void> resumeTransferTask(String taskId) {
    return _requestVoid('POST', '/transfer-tasks/$taskId/resume');
  }

  @override
  Future<void> pauseAllTransferTasks() {
    return _requestVoid('POST', '/transfer-tasks/pause-all');
  }

  @override
  Future<void> resumeAllTransferTasks() {
    return _requestVoid('POST', '/transfer-tasks/resume-all');
  }

  @override
  Future<void> cancelTransferTask(String taskId) {
    return _requestVoid('POST', '/transfer-tasks/$taskId/cancel');
  }

  @override
  Future<void> deleteTransferTask(String taskId) {
    return _requestVoid('DELETE', '/transfer-tasks/$taskId');
  }

  @override
  Future<void> clearTransferTasks(TransferDirection direction) {
    return _requestVoid(
      'DELETE',
      '/transfer-tasks',
      query: {'direction': direction.queryValue},
    );
  }

  @override
  Future<void> cancelLocalDownload(String downloadTaskId) async {
    final active = _activeDownloads.remove(downloadTaskId);
    if (active != null) {
      _serverManagedDownloadCancellations.add(downloadTaskId);
      active.client.close();
      await _deletePartialDownload(active.savePath);
      return;
    }
    final nativePath = _activeNativeDownloadPaths[downloadTaskId];
    if (nativePath != null) {
      _serverManagedDownloadCancellations.add(downloadTaskId);
      await _deletePartialDownload(nativePath);
    }
  }

  @override
  Future<void> pauseLocalDownload(String downloadTaskId) async {
    final active = _activeDownloads.remove(downloadTaskId);
    if (active != null) {
      _localDownloadPauses.add(downloadTaskId);
      active.client.close();
      return;
    }
    if (_activeNativeDownloadPaths.containsKey(downloadTaskId)) {
      _localDownloadPauses.add(downloadTaskId);
    }
  }

  @override
  Future<void> cancelDownloadTask(String downloadTaskId) {
    return _cancelDownload(downloadTaskId);
  }

  @override
  Future<void> cancelUploadTask(String uploadTaskId) async {
    final activeUpload = _activeUploads.remove(uploadTaskId);
    activeUpload?.close();
    if (AndroidUploads.isSupported) {
      try {
        await AndroidUploads.cancelUpload(uploadTaskId);
      } catch (_) {
        // The upload may be using the Dart path or may have already stopped.
      }
    }
    await _cancelUpload(uploadTaskId);
  }

  @override
  Future<PrepareDownloadInfo> prepareDownload(String fileId) {
    return _request<PrepareDownloadInfo>(
      'POST',
      '/downloads',
      body: {'fileId': fileId},
      parse: PrepareDownloadInfo.fromJson,
    );
  }

  @override
  Future<PrepareDownloadInfo> resumeDownload(String downloadTaskId) {
    return _request<PrepareDownloadInfo>(
      'POST',
      '/downloads/$downloadTaskId/resume',
      parse: PrepareDownloadInfo.fromJson,
    );
  }

  @override
  Future<PrepareDownloadInfo> downloadFile({
    required String fileId,
    required String savePath,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    PrepareDownloadInfo? info;
    var savedCompleteFile = false;
    try {
      info = await prepareDownload(fileId);
      final downloadedBytes = await _downloadPreparedFile(
        info: info,
        savePath: savePath,
        useBackendStream: Platform.isAndroid,
        onProgress: onProgress,
      );
      if (info.sizeBytes > 0 && downloadedBytes < info.sizeBytes) {
        throw const NetworkApiException('下载已中断');
      }
      savedCompleteFile =
          info.sizeBytes <= 0 || downloadedBytes >= info.sizeBytes;
      try {
        await _reportDownloadProgress(info.downloadTaskId, downloadedBytes);
        await _completeDownload(info.downloadTaskId);
      } catch (_) {
        // The file is already saved. Keep the user's download even if the
        // final task-status update cannot reach the server.
      }
      _notifyDownloadProgress(
        onProgress,
        DownloadProgress(
          downloadedBytes: info.sizeBytes,
          totalBytes: info.sizeBytes,
        ),
      );
      return info;
    } catch (error) {
      final apiError = normalizeApiError(error);
      final serverCancelHandledByTransferDeletion =
          info != null &&
          _serverManagedDownloadCancellations.remove(info.downloadTaskId);
      if (info != null) {
        _localDownloadPauses.remove(info.downloadTaskId);
      }
      if (info != null && !savedCompleteFile) {
        if (!serverCancelHandledByTransferDeletion) {
          try {
            await _requestVoid(
              'POST',
              '/downloads/${info.downloadTaskId}/pause',
            );
          } catch (_) {
            // Keep the original download failure as the user-facing error.
          }
        }
      }
      if (!savedCompleteFile && serverCancelHandledByTransferDeletion) {
        await _deletePartialDownload(savePath);
      }
      throw apiError;
    }
  }

  @override
  Future<PrepareDownloadInfo> downloadPreparedFile({
    required PrepareDownloadInfo info,
    required String savePath,
    int offset = 0,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    var savedCompleteFile = false;
    try {
      _localDownloadPauses.remove(info.downloadTaskId);
      final downloadedBytes = await _downloadPreparedFile(
        info: info,
        savePath: savePath,
        useBackendStream: true,
        offset: offset,
        onProgress: onProgress,
      );
      if (info.sizeBytes > 0 && downloadedBytes < info.sizeBytes) {
        throw const NetworkApiException('下载已中断');
      }
      savedCompleteFile =
          info.sizeBytes <= 0 || downloadedBytes >= info.sizeBytes;
      try {
        await _reportDownloadProgress(info.downloadTaskId, downloadedBytes);
        await _completeDownload(info.downloadTaskId);
      } catch (_) {
        // The file is already saved. Keep the user's download even if the
        // final task-status update cannot reach the server.
      }
      _notifyDownloadProgress(
        onProgress,
        DownloadProgress(
          downloadedBytes: info.sizeBytes,
          totalBytes: info.sizeBytes,
        ),
      );
      return info;
    } catch (error) {
      final apiError = normalizeApiError(error);
      final serverCancelHandledByTransferDeletion =
          _serverManagedDownloadCancellations.remove(info.downloadTaskId);
      if (!savedCompleteFile && !serverCancelHandledByTransferDeletion) {
        try {
          await _requestVoid(
            'POST',
            '/downloads/${info.downloadTaskId}/pause',
          );
        } catch (_) {
          // Keep the original download failure as the user-facing error.
        }
      }
      throw apiError;
    }
  }

  @override
  Future<void> downloadFilesBatch({
    required List<String> fileIds,
    required String savePath,
    int totalBytes = 0,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    var savedCompleteFile = false;
    http.Client? batchClient;
    try {
      final token = await _accessToken();
      final request = http.Request(
        'POST',
        _uri('/downloads/batch/stream', null),
      );
      request.headers['Accept'] = 'application/zip';
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.headers['Authorization'] = 'Bearer $token';
      request.body = jsonEncode({'fileIds': fileIds});

      batchClient = http.Client();
      late final http.StreamedResponse response;
      await _pageRequestPriorityGate.waitForPageRequests();
      response = await batchClient
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await http.Response.fromStream(response);
        _decodeEnvelope(body);
      }

      final resolvedTotalBytes = totalBytes > 0
          ? totalBytes
          : response.contentLength ?? 0;
      var downloadedBytes = 0;
      if (AndroidDownloads.isTargetPath(savePath)) {
        downloadedBytes = await _writeAndroidDownloadStream(
          savePath: savePath,
          stream: response.stream,
          totalBytes: resolvedTotalBytes,
          onProgress: onProgress,
          onChunkWritten: (currentBytes) async {
            downloadedBytes = currentBytes;
          },
        );
      } else {
        final file = File(savePath);
        final parent = file.parent;
        if (!await parent.exists()) {
          await parent.create(recursive: true);
        }
        final sink = file.openWrite();
        try {
          await for (final chunk in response.stream) {
            await _pageRequestPriorityGate.waitForPageRequests();
            sink.add(chunk);
            downloadedBytes += chunk.length;
            _notifyDownloadProgress(
              onProgress,
              DownloadProgress(
                downloadedBytes: downloadedBytes,
                totalBytes: resolvedTotalBytes,
              ),
            );
          }
        } finally {
          await sink.close();
        }
      }
      savedCompleteFile = true;
      _notifyDownloadProgress(
        onProgress,
        DownloadProgress(
          downloadedBytes: downloadedBytes,
          totalBytes: resolvedTotalBytes,
        ),
      );
    } catch (error) {
      final apiError = normalizeApiError(error);
      if (!savedCompleteFile) {
        await _deletePartialDownload(savePath);
      }
      throw apiError;
    } finally {
      batchClient?.close();
    }
  }

  @override
  Future<void> logout() async {
    final tokens = await _tokenStorage.read();
    try {
      await _requestVoid(
        'POST',
        '/auth/logout',
        body: {'refreshToken': tokens?.refreshToken},
      );
    } catch (_) {
      // Local logout should still clear credentials if the server is offline.
    }
    await _tokenStorage.clear();
  }

  @override
  void close() {
    for (final activeDownload in _activeDownloads.values) {
      activeDownload.client.close();
    }
    _activeDownloads.clear();
    for (final activeUpload in _activeUploads.values) {
      activeUpload.close();
    }
    _activeUploads.clear();
    _httpClient.close();
  }

  Future<int> _downloadPreparedFile({
    required PrepareDownloadInfo info,
    required String savePath,
    bool useBackendStream = false,
    int offset = 0,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final safeOffset = offset.clamp(0, info.sizeBytes).toInt();
    if (safeOffset > 0 && info.sizeBytes > 0) {
      _notifyDownloadProgress(
        onProgress,
        DownloadProgress(
          downloadedBytes: safeOffset,
          totalBytes: info.sizeBytes,
        ),
      );
      unawaited(
        _reportDownloadProgress(info.downloadTaskId, safeOffset).catchError(
          (_) {},
        ),
      );
    }
    // Android document providers are more reliable when the native side owns
    // both the HTTP stream and the output stream.
    final useNativeAndroidDownload = Platform.isAndroid;
    if (useNativeAndroidDownload &&
        useBackendStream &&
        AndroidDownloads.isTargetPath(savePath)) {
      final totalBytes = info.sizeBytes;
      if (totalBytes > 0 && safeOffset >= totalBytes) {
        _notifyDownloadProgress(
          onProgress,
          DownloadProgress(
            downloadedBytes: totalBytes,
            totalBytes: totalBytes,
          ),
        );
        await _reportDownloadProgress(info.downloadTaskId, totalBytes);
        return totalBytes;
      }
      _activeNativeDownloadPaths[info.downloadTaskId] = savePath;
      try {
        var downloadedBytes = safeOffset;
        var downloadedFromPresigned = false;
        var attemptOffset = safeOffset;
        var lastReportedBytes = safeOffset;
        final reportTimer = Stopwatch()..start();
        void handleNativeProgress(int sessionBytes) {
          downloadedBytes = _clampDownloadedBytes(
            attemptOffset + sessionBytes,
            totalBytes,
          );
          _notifyDownloadProgress(
            onProgress,
            DownloadProgress(
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
            ),
          );
          if (_shouldReportDownloadProgress(
            downloadedBytes: downloadedBytes,
            lastReportedBytes: lastReportedBytes,
            elapsed: reportTimer.elapsed,
            totalBytes: totalBytes,
          )) {
            lastReportedBytes = downloadedBytes;
            reportTimer
              ..reset()
              ..start();
            unawaited(
              _reportDownloadProgress(
                info.downloadTaskId,
                downloadedBytes,
              ).catchError((_) {}),
            );
          }
        }

        Future<int> downloadFromBackend(int offset) async {
          _throwIfAndroidNativeDownloadStopped(info.downloadTaskId);
          final token = await _accessToken();
          await _pageRequestPriorityGate.waitForPageRequests();
          _throwIfAndroidNativeDownloadStopped(info.downloadTaskId);
          attemptOffset = offset;
          final sessionBytes = await AndroidDownloads.downloadFile(
            path: savePath,
            url: _uri('/downloads/files/${info.fileId}/stream', {
              if (offset > 0) 'offset': offset.toString(),
            }),
            headers: {'Authorization': 'Bearer $token'},
            totalBytes: totalBytes,
            offset: offset,
            offsetAlreadyApplied: offset > 0,
            onProgress: handleNativeProgress,
          );
          _throwIfAndroidNativeDownloadStopped(info.downloadTaskId);
          return _clampDownloadedBytes(offset + sessionBytes, totalBytes);
        }

        if (!_isDeviceLocalhostUri(info.url)) {
          try {
            await _pageRequestPriorityGate.waitForPageRequests();
            _throwIfAndroidNativeDownloadStopped(info.downloadTaskId);
            attemptOffset = safeOffset;
            final sessionBytes = await AndroidDownloads.downloadFile(
              path: savePath,
              url: Uri.parse(info.url),
              headers: info.headers,
              totalBytes: totalBytes,
              offset: safeOffset,
              onProgress: handleNativeProgress,
            );
            _throwIfAndroidNativeDownloadStopped(info.downloadTaskId);
            downloadedBytes = _clampDownloadedBytes(
              safeOffset + sessionBytes,
              totalBytes,
            );
            downloadedFromPresigned = true;
          } catch (_) {
            // Fall back to the authenticated backend stream below.
          }
        }
        if (!downloadedFromPresigned) {
          var backendOffset = await _currentAndroidDownloadSize(
            savePath,
            totalBytes,
          );
          downloadedBytes = backendOffset;
          if (backendOffset > safeOffset) {
            _notifyDownloadProgress(
              onProgress,
              DownloadProgress(
                downloadedBytes: downloadedBytes,
                totalBytes: totalBytes,
              ),
            );
          }
          if (totalBytes > 0 && backendOffset >= totalBytes) {
            await _reportDownloadProgress(info.downloadTaskId, totalBytes);
          } else {
            for (var retryCount = 0; ; retryCount++) {
              try {
                downloadedBytes = await downloadFromBackend(backendOffset);
                break;
              } catch (backendError) {
                if (!_isTransientAndroidNativeDownloadError(backendError) ||
                    retryCount >= _androidNativeDownloadMaxRetries) {
                  rethrow;
                }
                _throwIfAndroidNativeDownloadStopped(info.downloadTaskId);
                final retryOffset = await _currentAndroidDownloadSize(
                  savePath,
                  totalBytes,
                );
                downloadedBytes = retryOffset;
                backendOffset = retryOffset;
                _notifyDownloadProgress(
                  onProgress,
                  DownloadProgress(
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes,
                  ),
                );
                if (totalBytes > 0 && retryOffset >= totalBytes) {
                  await _reportDownloadProgress(
                    info.downloadTaskId,
                    totalBytes,
                  );
                  break;
                }
                if (retryOffset > lastReportedBytes) {
                  lastReportedBytes = retryOffset;
                  reportTimer
                    ..reset()
                    ..start();
                  unawaited(
                    _reportDownloadProgress(
                      info.downloadTaskId,
                      retryOffset,
                    ).catchError((_) {}),
                  );
                }
                await Future<void>.delayed(
                  _androidNativeDownloadRetryDelay(retryCount + 1),
                );
              }
            }
          }
        }
        _notifyDownloadProgress(
          onProgress,
          DownloadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          ),
        );
        return downloadedBytes;
      } finally {
        _activeNativeDownloadPaths.remove(info.downloadTaskId);
      }
    }

    if (info.sizeBytes > 0 && safeOffset >= info.sizeBytes) {
      _notifyDownloadProgress(
        onProgress,
        DownloadProgress(
          downloadedBytes: info.sizeBytes,
          totalBytes: info.sizeBytes,
        ),
      );
      await _reportDownloadProgress(info.downloadTaskId, info.sizeBytes);
      return info.sizeBytes;
    }

    final downloadClient = http.Client();
    _activeDownloads[info.downloadTaskId] = _ActiveDownload(
      savePath: savePath,
      client: downloadClient,
    );
    try {
      final response = await _openDownloadStream(
        info,
        downloadClient,
        useBackendStream: useBackendStream,
        offset: safeOffset,
      );

      final totalBytes = info.sizeBytes > 0
          ? info.sizeBytes
          : response.contentLength ?? 0;
      var downloadedBytes = safeOffset;
      var lastReportedBytes = safeOffset;
      final reportTimer = Stopwatch()..start();

      if (AndroidDownloads.isTargetPath(savePath)) {
        return _writeAndroidDownloadStream(
          savePath: savePath,
          stream: response.stream,
          totalBytes: totalBytes,
          offset: safeOffset,
          onProgress: (progress) {
            downloadedBytes = progress.downloadedBytes;
            _notifyDownloadProgress(onProgress, progress);
          },
          onChunkWritten: (_) async {
            if (_shouldReportDownloadProgress(
              downloadedBytes: downloadedBytes,
              lastReportedBytes: lastReportedBytes,
              elapsed: reportTimer.elapsed,
              totalBytes: totalBytes,
            )) {
              try {
                await _reportDownloadProgress(
                  info.downloadTaskId,
                  downloadedBytes,
                );
              } catch (_) {
                // Keep downloading even if the task-center progress update is
                // temporarily unavailable.
              }
              lastReportedBytes = downloadedBytes;
              reportTimer
                ..reset()
                ..start();
            }
          },
        );
      }

      final file = File(savePath);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      final existingBytes = await file.exists() ? await file.length() : 0;
      final writeMode = safeOffset > 0 && existingBytes == safeOffset
          ? FileMode.append
          : FileMode.write;
      final sink = file.openWrite(mode: writeMode);
      try {
        await for (final chunk in response.stream) {
          await _pageRequestPriorityGate.waitForPageRequests();
          sink.add(chunk);
          downloadedBytes += chunk.length;
          _notifyDownloadProgress(
            onProgress,
            DownloadProgress(
              downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          ),
        );
          if (_shouldReportDownloadProgress(
            downloadedBytes: downloadedBytes,
            lastReportedBytes: lastReportedBytes,
            elapsed: reportTimer.elapsed,
            totalBytes: totalBytes,
          )) {
            try {
              await _reportDownloadProgress(
                info.downloadTaskId,
                downloadedBytes,
              );
            } catch (_) {
              // Keep downloading even if the task-center progress update is
              // temporarily unavailable.
            }
            lastReportedBytes = downloadedBytes;
            reportTimer
              ..reset()
              ..start();
          }
        }
      } finally {
        await sink.close();
      }
      return downloadedBytes;
    } finally {
      _activeDownloads.remove(info.downloadTaskId);
      downloadClient.close();
    }
  }

  Future<int> _writeAndroidDownloadStream({
    required String savePath,
    required Stream<List<int>> stream,
    required int totalBytes,
    int offset = 0,
    void Function(DownloadProgress progress)? onProgress,
    Future<void> Function(int downloadedBytes)? onChunkWritten,
  }) async {
    String? sessionId;
    var downloadedBytes = offset;
    try {
      sessionId = await AndroidDownloads.openDownload(
        savePath,
        append: offset > 0,
      );
      await for (final chunk in stream) {
        await _pageRequestPriorityGate.waitForPageRequests();
        await AndroidDownloads.writeDownloadChunk(sessionId, chunk);
        downloadedBytes += chunk.length;
        _notifyDownloadProgress(
          onProgress,
          DownloadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          ),
        );
        await onChunkWritten?.call(downloadedBytes);
      }
      await AndroidDownloads.closeDownload(sessionId);
      return downloadedBytes;
    } catch (_) {
      if (sessionId != null) {
        try {
          await AndroidDownloads.cancelDownload(sessionId);
        } catch (_) {
          // Keep the original download failure as the user-facing error.
        }
      }
      rethrow;
    }
  }

  Future<http.StreamedResponse> _openDownloadStream(
    PrepareDownloadInfo info,
    http.Client downloadClient, {
    bool useBackendStream = false,
    int offset = 0,
  }) async {
    if (useBackendStream) {
      return _openBackendDownloadStream(info, downloadClient, offset: offset);
    }

    try {
      final requestHeaders = {
        ...info.headers,
        if (offset > 0) 'Range': 'bytes=$offset-',
      };
      final response = await _sendDownloadRequest(
        Uri.parse(info.url),
        client: downloadClient,
        headers: requestHeaders,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (offset <= 0 || response.statusCode == 206) {
          return response;
        }
        unawaited(response.stream.drain<void>());
      } else {
        unawaited(response.stream.drain<void>());
      }
    } catch (_) {
      // Fall back to the authenticated backend stream below.
    }

    return _openBackendDownloadStream(info, downloadClient, offset: offset);
  }

  Future<http.StreamedResponse> _openBackendDownloadStream(
    PrepareDownloadInfo info,
    http.Client downloadClient,
    {
    int offset = 0,
  }) async {
    final token = await _accessToken();
    final response = await _sendDownloadRequest(
      _uri('/downloads/files/${info.fileId}/stream', {
        if (offset > 0) 'offset': offset.toString(),
      }),
      client: downloadClient,
      accessToken: token,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    throw ApiHttpException(
      '下载失败，请稍后重试',
      statusCode: response.statusCode,
    );
  }

  Future<http.StreamedResponse> _sendDownloadRequest(
    Uri uri, {
    http.Client? client,
    Map<String, String> headers = const {},
    String? accessToken,
  }) {
    final request = http.Request('GET', uri);
    request.headers.addAll(headers);
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    return (client ?? _httpClient)
        .send(request)
        .timeout(const Duration(seconds: 30));
  }

  bool _isDeviceLocalhostUri(String value) {
    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  int _clampDownloadedBytes(int bytes, int totalBytes) {
    if (totalBytes <= 0) {
      return bytes < 0 ? 0 : bytes;
    }
    return bytes.clamp(0, totalBytes).toInt();
  }

  Future<int> _currentAndroidDownloadSize(
    String savePath,
    int totalBytes,
  ) async {
    final size = await AndroidDownloads.size(savePath);
    return _clampDownloadedBytes(size, totalBytes);
  }

  bool _isTransientAndroidNativeDownloadError(Object error) {
    final message = _platformErrorMessage(error).toLowerCase();
    if (message.isEmpty) {
      return false;
    }
    return message.contains('java.net.socketexception') ||
        message.contains('software caused connection abort') ||
        message.contains('connection reset') ||
        message.contains('broken pipe') ||
        message.contains('java.io.eofexception') ||
        message.contains('unexpected end of stream') ||
        message.contains('read timed out') ||
        message.contains('timeout');
  }

  String _platformErrorMessage(Object error) {
    if (error is PlatformException) {
      return [
        error.code,
        if (error.message != null) error.message,
        if (error.details != null) error.details.toString(),
      ].join(' ');
    }
    return error.toString();
  }

  Duration _androidNativeDownloadRetryDelay(int attempt) {
    final multiplier = attempt
        .clamp(1, _androidNativeDownloadMaxRetries)
        .toInt();
    return Duration(
      milliseconds:
          _androidNativeDownloadRetryBaseDelay.inMilliseconds * multiplier,
    );
  }

  void _throwIfAndroidNativeDownloadStopped(String downloadTaskId) {
    if (_serverManagedDownloadCancellations.contains(downloadTaskId)) {
      throw const NetworkApiException('下载已取消');
    }
    if (_localDownloadPauses.contains(downloadTaskId)) {
      throw const NetworkApiException('下载已暂停，可在传输页面继续');
    }
  }

  bool _shouldReportDownloadProgress({
    required int downloadedBytes,
    required int lastReportedBytes,
    required Duration elapsed,
    required int totalBytes,
  }) {
    if (downloadedBytes <= lastReportedBytes) {
      return false;
    }
    if (totalBytes > 0 && downloadedBytes >= totalBytes) {
      return true;
    }
    const reportEveryBytes = 512 * 1024;
    return downloadedBytes - lastReportedBytes >= reportEveryBytes ||
        elapsed >= const Duration(seconds: 1);
  }

  void _notifyDownloadProgress(
    void Function(DownloadProgress progress)? onProgress,
    DownloadProgress progress,
  ) {
    try {
      onProgress?.call(progress);
    } catch (_) {
      // UI progress observers must not interrupt the underlying transfer.
    }
  }

  Stream<List<int>> _progressStream(
    Stream<List<int>> source,
    void Function(int uploadedBytes)? onProgress, {
    Future<void> Function()? waitForPageRequests,
  }) async* {
    var uploadedBytes = 0;
    await for (final chunk in source) {
      await waitForPageRequests?.call();
      uploadedBytes += chunk.length;
      onProgress?.call(uploadedBytes);
      yield chunk;
    }
  }

  Future<void> _reportDownloadProgress(String downloadTaskId, int bytes) {
    return _requestVoid(
      'POST',
      '/downloads/$downloadTaskId/progress',
      body: {'downloadedBytes': bytes},
    );
  }

  Future<void> _completeDownload(String downloadTaskId) {
    return _requestVoid('POST', '/downloads/$downloadTaskId/complete');
  }

  Future<void> _cancelDownload(String downloadTaskId) {
    return _requestVoid('POST', '/downloads/$downloadTaskId/cancel');
  }

  Future<void> _cancelUpload(String uploadTaskId) {
    return _requestVoid('POST', '/uploads/$uploadTaskId/cancel');
  }

  Future<void> _pauseUpload(String uploadTaskId) {
    return _requestVoid('POST', '/uploads/$uploadTaskId/pause');
  }

  Future<void> _deletePartialDownload(String savePath) async {
    try {
      if (AndroidDownloads.isTargetPath(savePath)) {
        await AndroidDownloads.deleteDownload(savePath);
        return;
      }
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // A failed cleanup should not hide the original download error.
    }
  }

  Future<T> _request<T>(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
    required T Function(Map<String, dynamic>) parse,
    http.Client? client,
  }) async {
    final json = await _sendJson(
      method,
      path,
      query: query,
      body: body,
      authenticated: authenticated,
      client: client,
    );
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw const JsonApiException('服务端响应缺�?data 对象');
    }
    return parse(data);
  }

  Future<List<T>> _requestList<T>(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
    required T Function(Map<String, dynamic>) parse,
    http.Client? client,
  }) async {
    final json = await _sendJson(
      method,
      path,
      query: query,
      body: body,
      authenticated: authenticated,
      client: client,
    );
    final data = json['data'];
    if (data is! List<dynamic>) {
      throw const JsonApiException('服务端响应缺�?data 列表');
    }
    return data.cast<Map<String, dynamic>>().map(parse).toList();
  }

  Future<PageResult<T>> _requestPage<T>(
    String method,
    String path, {
    Map<String, String>? query,
    required T Function(Map<String, dynamic>) parse,
    http.Client? client,
  }) async {
    return _request<PageResult<T>>(
      method,
      path,
      query: query,
      parse: (json) => PageResult<T>.fromJson(json, parse),
      client: client,
    );
  }

  Future<void> _requestVoid(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    await _sendJson(method, path, query: query, body: body);
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    bool authenticated = true,
    bool retryOnUnauthorized = true,
    http.Client? client,
  }) async {
    try {
      Future<Map<String, dynamic>> sendRequest() async {
        final token = authenticated ? await _accessToken() : null;
        final response = await _send(
          method,
          path,
          query: query,
          body: body,
          accessToken: token,
          client: client,
        );

        if (response.statusCode == 401 &&
            authenticated &&
            method == 'GET' &&
            retryOnUnauthorized) {
          final refreshed = await _refreshAccessToken();
          final retryResponse = await _send(
            method,
            path,
            query: query,
            body: body,
            accessToken: refreshed,
            client: client,
          );
          return _decodeEnvelope(retryResponse);
        }

        return _decodeEnvelope(response);
      }

      if (method == 'GET') {
        return await _pageRequestPriorityGate.run(sendRequest);
      }
      return await sendRequest();
    } catch (error) {
      throw normalizeApiError(error);
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, Object?>? body,
    String? accessToken,
    http.Client? client,
  }) {
    final uri = _uri(path, query);
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
    final encodedBody = body == null ? null : jsonEncode(body);

    final requestClient = client ?? _httpClient;
    final request = switch (method) {
      'GET' => requestClient.get(uri, headers: headers),
      'POST' => requestClient.post(uri, headers: headers, body: encodedBody),
      'PATCH' => requestClient.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => requestClient.delete(uri, headers: headers, body: encodedBody),
      _ => throw ArgumentError.value(method, 'method', 'Unsupported method'),
    };

    return request.timeout(_timeout);
  }

  Map<String, dynamic> _decodeEnvelope(http.Response response) {
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    final success = decoded['success'] as bool? ?? false;
    if (response.statusCode >= 200 && response.statusCode < 300 && success) {
      return decoded;
    }

    final error = decoded['error'];
    final code = error is Map<String, dynamic>
        ? error['code'] as String?
        : null;
    final message = error is Map<String, dynamic>
        ? _localizedServerMessage(
            error['code'] as String?,
            error['message'] as String?,
          )
        : '请求失败，请稍后重试';
    if (response.statusCode == 401) {
      throw UnauthorizedApiException(message, code: code);
    }
    throw ApiHttpException(
      message,
      statusCode: response.statusCode,
      code: code,
    );
  }

  Future<String> _accessToken() async {
    final tokens = await _tokenStorage.read();
    if (tokens == null) {
      throw const UnauthorizedApiException('请先登录');
    }
    if (!tokens.shouldRefresh) {
      return tokens.accessToken;
    }
    return _refreshAccessToken();
  }

  String _localizedServerMessage(String? code, String? fallback) {
    return switch (code) {
      'upload_paused' => '上传已暂停，可在传输页面继续',
      'upload_offset_mismatch' => '上传进度不一致，请重新继续传输',
      'download_canceled' => '下载已取消',
      'download_completed' => '下载已完成',
      _ => fallback?.trim().isNotEmpty == true
          ? fallback!.trim()
          : '请求失败，请稍后重试',
    };
  }

  Future<String> _refreshAccessToken() async {
    final tokens = await _tokenStorage.read();
    if (tokens == null) {
      throw const UnauthorizedApiException('请先登录');
    }

    try {
      final response = await _send(
        'POST',
        '/auth/refresh',
        body: {'refreshToken': tokens.refreshToken},
      );
      final json = _decodeEnvelope(response);
      final data = json['data'];
      if (data is! Map<String, dynamic>) {
        throw const UnauthorizedApiException('登录状态已失效');
      }
      final session = AuthSession.fromJson(data);
      await _saveSession(session);
      return session.accessToken;
    } catch (error) {
      final apiError = normalizeApiError(error);
      if (apiError is UnauthorizedApiException) {
        await _tokenStorage.clear();
      }
      throw apiError;
    }
  }

  Future<void> _saveSession(AuthSession session) {
    return _tokenStorage.save(
      TokenPair(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
        accessTokenExpiresAt: session.accessTokenExpiresAt,
        refreshTokenExpiresAt: session.refreshTokenExpiresAt,
      ),
    );
  }

  Uri _uri(String path, Map<String, String>? query) {
    final normalizedBase = _baseUrl.path.endsWith('/')
        ? _baseUrl.path.substring(0, _baseUrl.path.length - 1)
        : _baseUrl.path;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return _baseUrl.replace(
      path: '$normalizedBase$normalizedPath',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Future<Map<String, Object?>> _deviceMetadata() async {
    return {
      'deviceName': await CurrentDevice.resolveName(),
      'platform': _devicePlatform,
      'appVersion': '1.0',
    };
  }

  String get _devicePlatform {
    const override = String.fromEnvironment('LINKVAULT_CLIENT_PLATFORM');
    if (override.isNotEmpty) {
      return override;
    }
    return CurrentDevice.platform;
  }
}
