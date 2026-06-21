import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/app_dependencies.dart';
import '../../../app/router/app_router.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/network/linkvault_api_client.dart';
import '../../../core/network/linkvault_models.dart';
import '../../../core/platform/android_downloads.dart';
import '../../../core/platform/android_uploads.dart';
import '../../../shared/widgets/app_feedback.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/folder_picker_dialog.dart';
import '../../../shared/widgets/input_constraints.dart';
import '../../../shared/widgets/vault_widgets.dart';

const String _rootFolderId = '__root__';

class FileListPage extends StatefulWidget {
  const FileListPage({super.key});

  @override
  State<FileListPage> createState() => _FileListPageState();
}

class _FileListPageState extends State<FileListPage> {
  final List<_FolderCrumb> _folderPath = [
    const _FolderCrumb(id: _rootFolderId, name: '根目录'),
  ];
  late Future<PageResult<FileNode>> _future;
  final Set<String> _selectedNodeIds = <String>{};
  bool _initialized = false;
  bool _uploading = false;

  String? get _currentParentId {
    final id = _folderPath.last.id;
    return id == _rootFolderId ? null : id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _load();
      _initialized = true;
    }
  }

  Future<PageResult<FileNode>> _load() async {
    final api = DependenciesScope.of(context).apiClient;
    final parentId = _currentParentId;
    const perPage = 100;
    final firstPage = await api.files(
      parentId: parentId,
      perPage: perPage,
    );
    if (firstPage.meta.totalPages <= 1) {
      return firstPage;
    }

    final items = List<FileNode>.of(firstPage.items);
    for (var page = 2; page <= firstPage.meta.totalPages; page++) {
      final result = await api.files(
        parentId: parentId,
        page: page,
        perPage: perPage,
      );
      items.addAll(result.items);
    }
    return PageResult<FileNode>(
      items: items,
      meta: PageMeta(
        page: firstPage.meta.page,
        perPage: perPage,
        total: firstPage.meta.total,
        totalPages: firstPage.meta.totalPages,
      ),
    );
  }

  void _reload() {
    setState(() {
      _selectedNodeIds.clear();
      _future = _load();
    });
  }

  void _toggleNodeSelection(FileNode node, bool selected) {
    setState(() {
      if (selected) {
        if (!_selectedNodeIds.contains(node.id) &&
            _selectedNodeIds.length >= 10) {
          _showMessage('一次最多选择 10 个项目');
          return;
        }
        _selectedNodeIds.add(node.id);
      } else {
        _selectedNodeIds.remove(node.id);
      }
    });
  }

  void _toggleAllNodes(List<FileNode> nodes, bool selected) {
    final nodeIds = nodes.map((node) => node.id).toList(growable: false);
    setState(() {
      if (selected) {
        final unselectedIds = nodeIds
            .where((nodeId) => !_selectedNodeIds.contains(nodeId))
            .toList(growable: false);
        final remainingSlots = 10 - _selectedNodeIds.length;
        if (remainingSlots <= 0) {
          _showMessage('一次最多选择 10 个项目');
          return;
        }
        _selectedNodeIds.addAll(unselectedIds.take(remainingSlots));
        if (unselectedIds.length > remainingSlots) {
          _showMessage('一次最多选择 10 个项目');
        }
      } else {
        final nodeIdSet = nodeIds.toSet();
        _selectedNodeIds.removeWhere(nodeIdSet.contains);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedNodeIds.clear();
    });
  }

  Future<void> _search() async {
    final query = await showDialog<String>(
      context: context,
      builder: (context) => const _SearchDialog(),
    );
    if (query == null || query.trim().isEmpty || !mounted) {
      return;
    }
    final queryError = requiredTextError(query, label: '搜索内容');
    if (queryError != null) {
      _showMessage(queryError);
      return;
    }
    setState(() {
      _selectedNodeIds.clear();
      _future = DependenciesScope.of(context).apiClient.searchFiles(
        query: query.trim(),
        scope: FileSearchScope.all,
        parentId: _currentParentId,
      );
    });
  }

  Future<void> _createFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _CreateFolderDialog(),
    );
    if (name == null || name.trim().isEmpty || !mounted) {
      return;
    }
    final nameError = requiredTextError(name, label: '文件夹名称');
    if (nameError != null) {
      _showMessage(nameError);
      return;
    }
    try {
      await DependenciesScope.of(
        context,
      ).apiClient.createFolder(parentId: _currentParentId, name: name.trim());
      if (mounted) {
        _reload();
      }
    } catch (error) {
      if (mounted) {
        final apiError = normalizeApiError(error);
        _showMessage(
          apiError.code == 'name_conflict' ? '名称已存在' : apiError.message,
          type: apiError.code == 'name_conflict'
              ? AppNoticeType.warning
              : AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _upload() async {
    final targets = await _pickUploadTargets();
    if (targets == null || targets.isEmpty || !mounted || _uploading) {
      return;
    }

    setState(() {
      _uploading = true;
    });
    try {
      final parentId = _currentParentId;
      setState(() {
        _selectedNodeIds.clear();
      });
      showCompactAppSnackBar(context, '已加入传输队列中');
      final dependencies = DependenciesScope.of(context);
      dependencies.transferTaskEvents.markChanged();
      unawaited(_runUploadQueue(targets, parentId));
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
        });
      }
    }
  }

  Future<List<_UploadTarget>?> _pickUploadTargets() async {
    if (!AndroidUploads.isSupported) {
      return showDialog<List<_UploadTarget>>(
        context: context,
        builder: (context) => const _UploadTargetDialog(),
      );
    }

    try {
      final files = await AndroidUploads.pickFiles();
      return files
          .map(
            (file) => _UploadTarget.file(
              path: AndroidUploads.targetPath(file),
              name: file.name,
            ),
          )
          .toList();
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          error.code == 'picker_active'
              ? '已有文件选择窗口正在打开'
              : '无法选择上传文件，请稍后重试',
          type: AppNoticeType.error,
        );
      }
      return null;
    } catch (_) {
      if (mounted) {
        _showMessage('无法选择上传文件，请稍后重试', type: AppNoticeType.error);
      }
      return null;
    }
  }

  Future<void> _runUploadQueue(List<_UploadTarget> targets, String? parentId) async {
    final summary = _UploadBatchSummary();
    try {
      final api = DependenciesScope.of(context).apiClient;
      for (final target in targets) {
        switch (target.type) {
          case _UploadTargetType.file:
            await _uploadFileTarget(target, parentId, summary);
          case _UploadTargetType.folder:
            await _uploadFolderTarget(api, target, parentId, summary);
        }
      }
      if (!mounted) {
        return;
      }
      DependenciesScope.of(context).transferTaskEvents.markChanged();
      if (summary.hasSuccess) {
        _reload();
      }
      if (summary.failures.isNotEmpty) {
        _showMessage(_uploadResultMessage(summary), type: AppNoticeType.error);
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          normalizeApiError(error).message,
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _uploadFileTarget(
    _UploadTarget target,
    String? parentId,
    _UploadBatchSummary summary,
  ) async {
    try {
      final dependencies = DependenciesScope.of(context);
      final record = await dependencies.transferResumeService.registerUpload(
        path: target.path,
        fileName: target.name,
        parentId: parentId,
      );
      dependencies.transferTaskEvents.markChanged();
      await dependencies.apiClient.uploadPreparedFile(
        uploadTaskId: record.sourceId,
        path: target.path,
        fileName: target.name,
        onProgress: (_) {
          if (mounted) {
            DependenciesScope.of(context).transferTaskEvents.markChanged();
          }
        },
      );
      await dependencies.transferResumeService.complete(record.taskId);
      summary.files++;
      if (mounted) {
        DependenciesScope.of(context).transferTaskEvents.markChanged();
      }
    } catch (error) {
      summary.failures.add(
        _UploadFailure(target.name, normalizeApiError(error).message),
      );
    }
  }

  Future<void> _uploadFolderTarget(
    LinkVaultApi api,
    _UploadTarget target,
    String? parentId,
    _UploadBatchSummary summary,
  ) async {
    FileNode folder;
    try {
      folder = await api.createFolder(parentId: parentId, name: target.name);
      summary.folders++;
    } catch (error) {
      summary.failures.add(
        _UploadFailure(target.name, normalizeApiError(error).message),
      );
      return;
    }

    try {
      await for (final entity in Directory(
        target.path,
      ).list(followLinks: false)) {
        final name = _pathBaseName(entity.path);
        final entityType = await FileSystemEntity.type(
          entity.path,
          followLinks: false,
        );
        switch (entityType) {
          case FileSystemEntityType.file:
            await _uploadFileTarget(
              _UploadTarget.file(path: entity.path, name: name),
              folder.id,
              summary,
            );
          case FileSystemEntityType.directory:
            await _uploadFolderTarget(
              api,
              _UploadTarget.folder(path: entity.path, name: name),
              folder.id,
              summary,
            );
          case FileSystemEntityType.link:
          case FileSystemEntityType.notFound:
          case FileSystemEntityType.pipe:
          case FileSystemEntityType.unixDomainSock:
            summary.failures.add(_UploadFailure(name, '不支持上传该目标类型'));
        }
      }
    } catch (error) {
      summary.failures.add(
        _UploadFailure(target.name, normalizeApiError(error).message),
      );
    }
  }

  String _uploadResultMessage(_UploadBatchSummary summary) {
    final uploadedParts = [
      if (summary.files > 0) '${summary.files} 个文件',
      if (summary.folders > 0) '${summary.folders} 个文件夹',
    ];
    final uploadedText = uploadedParts.isEmpty
        ? '没有完成任何上传'
        : '已上传 ${uploadedParts.join('、')}';
    if (summary.failures.isEmpty) {
      return uploadedText;
    }
    return '$uploadedText，${summary.failures.length} 个项目上传失败，请稍后重试';
  }

  Future<bool> _download(FileNode node) async {
    if (node.type == FileNodeType.folder) {
      return _downloadFolders([node]);
    }

    final savePath = await _pickDownloadPath(node.name);
    if (savePath == null || !mounted) {
      return false;
    }

    final transferTaskEvents = DependenciesScope.of(context).transferTaskEvents;

    showCompactAppSnackBar(context, '已加入传输队列中');
    transferTaskEvents.markChanged();

    unawaited(() async {
      try {
        final dependencies = DependenciesScope.of(context);
        final info = await dependencies.transferResumeService.registerDownload(
          fileId: node.id,
          savePath: savePath,
        );
        transferTaskEvents.markChanged();
        await dependencies.apiClient.downloadPreparedFile(
          info: info,
          savePath: savePath,
          onProgress: (value) {
            transferTaskEvents.markChanged();
          },
        );
        await dependencies.transferResumeService.complete(info.downloadTaskId);
        if (!mounted) {
          return;
        }
        transferTaskEvents.markChanged();
        if (info.fileId == node.id) {
          _reload();
        }
      } catch (error) {
        if (mounted) {
          _showMessage(
            normalizeApiError(error).message,
            type: AppNoticeType.error,
          );
        }
      }
    }());
    return true;
  }

  Future<void> _downloadNodes(List<FileNode> nodes) async {
    if (nodes.isEmpty) {
      return;
    }
    if (!_canRunBatch(nodes)) {
      return;
    }
    if (nodes.any((node) => node.type == FileNodeType.folder) ||
        defaultTargetPlatform == TargetPlatform.android) {
      await _downloadFolders(nodes);
      return;
    }
    if (nodes.length == 1 && nodes.single.type == FileNodeType.file) {
      final started = await _download(nodes.single);
      if (started && mounted) {
        _clearSelection();
      }
      return;
    }

    final savePath = await _pickBatchDownloadPath(nodes);
    if (savePath == null || !mounted) {
      return;
    }

    final transferTaskEvents = DependenciesScope.of(context).transferTaskEvents;
    showCompactAppSnackBar(context, '已加入传输队列中');
    transferTaskEvents.markChanged();
    _clearSelection();

    unawaited(() async {
      try {
        await DependenciesScope.of(context).apiClient.downloadFilesBatch(
          fileIds: nodes.map((node) => node.id).toList(),
          savePath: savePath,
          totalBytes: nodes.fold<int>(
            0,
            (total, node) => total + node.sizeBytes,
          ),
          onProgress: (_) {
            transferTaskEvents.markChanged();
          },
        );
        if (!mounted) {
          return;
        }
        transferTaskEvents.markChanged();
      } catch (error) {
        if (mounted) {
          _showMessage(
            normalizeApiError(error).message,
            type: AppNoticeType.error,
          );
        }
      }
    }());
  }

  Future<bool> _downloadFolders(List<FileNode> nodes) async {
    final targetRoot = await _pickFolderDownloadRoot();
    if (targetRoot == null || !mounted) {
      return false;
    }
    final canOverwrite = await _confirmDownloadConflictsIfNeeded(
      nodes.map((node) => _downloadTargetPath(targetRoot, node.name)),
    );
    if (!canOverwrite || !mounted) {
      return false;
    }

    final dependencies = DependenciesScope.of(context);
    final transferTaskEvents = dependencies.transferTaskEvents;
    final totalBytes = nodes.fold<int>(
      0,
      (total, node) => total + node.sizeBytes,
    );
    var downloadedBytes = 0;

    showCompactAppSnackBar(context, '已加入传输队列中');
    transferTaskEvents.markChanged();
    _clearSelection();

    unawaited(() async {
      try {
        final api = dependencies.apiClient;
        for (final node in nodes) {
          if (node.type == FileNodeType.folder) {
            await _downloadFolderRecursive(
              api: api,
              dependencies: dependencies,
              folder: node,
              targetRoot: targetRoot,
              relativeRoot: node.name,
              downloadedBytes: () => downloadedBytes,
              setDownloadedBytes: (value) => downloadedBytes = value,
              totalBytes: totalBytes,
              onProgress: (_) {
                transferTaskEvents.markChanged();
              },
            );
          } else {
            final info =
                await dependencies.transferResumeService.registerDownload(
              fileId: node.id,
              savePath: _downloadTargetPath(targetRoot, node.name),
            );
            transferTaskEvents.markChanged();
            await dependencies.apiClient.downloadPreparedFile(
              info: info,
              savePath: _downloadTargetPath(targetRoot, node.name),
              onProgress: (_) {
                transferTaskEvents.markChanged();
              },
            );
            await dependencies.transferResumeService.complete(
              info.downloadTaskId,
            );
            downloadedBytes += node.sizeBytes;
          }
        }
        if (!mounted) {
          return;
        }
        transferTaskEvents.markChanged();
      } catch (error) {
        if (mounted) {
          _showMessage(
            normalizeApiError(error).message,
            type: AppNoticeType.error,
          );
        }
      }
    }());
    return true;
  }
  Future<void> _downloadFolderRecursive({
    required LinkVaultApi api,
    required AppDependencies dependencies,
    required FileNode folder,
    required _DownloadRoot targetRoot,
    required String relativeRoot,
    required int Function() downloadedBytes,
    required ValueChanged<int> setDownloadedBytes,
    required int totalBytes,
    required ValueChanged<DownloadProgress> onProgress,
  }) async {
    final folderPath = _downloadTargetPath(targetRoot, relativeRoot);
    if (AndroidDownloads.isTargetPath(folderPath)) {
      await AndroidDownloads.createFolder(folderPath);
    } else {
      final directory = Directory(folderPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    }

    var page = 1;
    while (true) {
      final result = await api.files(
        parentId: folder.id,
        page: page,
        perPage: 100,
      );
      for (final child in result.items) {
        final childRelativePath = _joinRelativePath(relativeRoot, child.name);
        if (child.type == FileNodeType.folder) {
          await _downloadFolderRecursive(
            api: api,
            dependencies: dependencies,
            folder: child,
            targetRoot: targetRoot,
            relativeRoot: childRelativePath,
            downloadedBytes: downloadedBytes,
            setDownloadedBytes: setDownloadedBytes,
            totalBytes: totalBytes,
            onProgress: onProgress,
          );
          continue;
        }

        final beforeFileBytes = downloadedBytes();
        final info = await dependencies.transferResumeService.registerDownload(
          fileId: child.id,
          savePath: _downloadTargetPath(targetRoot, childRelativePath),
        );
        dependencies.transferTaskEvents.markChanged();
        await dependencies.apiClient.downloadPreparedFile(
          info: info,
          savePath: _downloadTargetPath(targetRoot, childRelativePath),
          onProgress: (value) {
            onProgress(
              DownloadProgress(
                downloadedBytes: beforeFileBytes + value.downloadedBytes,
                totalBytes: totalBytes,
              ),
            );
          },
        );
        await dependencies.transferResumeService.complete(info.downloadTaskId);
        setDownloadedBytes(beforeFileBytes + child.sizeBytes);
      }
      if (page >= result.meta.totalPages) {
        return;
      }
      page++;
    }
  }

  void _openFolder(FileNode folder) {
    if (folder.type != FileNodeType.folder) {
      return;
    }
    setState(() {
      _selectedNodeIds.clear();
      _folderPath.add(_FolderCrumb(id: folder.id, name: folder.name));
      _future = _load();
    });
  }

  void _goToFolder(int index) {
    setState(() {
      _selectedNodeIds.clear();
      _folderPath.removeRange(index + 1, _folderPath.length);
      _future = _load();
    });
  }

  Future<String?> _pickDownloadPath(String fileName) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (!await _ensureAndroidDownloadPermissions()) {
        return null;
      }
      final treeUri = await AndroidDownloads.pickFolderUri();
      if (treeUri == null || treeUri.isEmpty) {
        return null;
      }
      final savePath = AndroidDownloads.targetPath(
        treeUri: treeUri,
        relativePath: fileName,
      );
      return await _confirmDownloadConflictsIfNeeded([savePath])
          ? savePath
          : null;
    }

    try {
      final isWindows = defaultTargetPlatform == TargetPlatform.windows;
      final saveLocation = await getSaveLocation(
        suggestedName: isWindows
            ? _baseNameWithoutExtension(fileName)
            : fileName,
        acceptedTypeGroups: [_acceptedTypeGroupFor(fileName)],
        confirmButtonText: '下载',
        canCreateDirectories: true,
      );
      final path = saveLocation?.path;
      if (path == null) {
        return null;
      }
      final savePath = isWindows ? _ensureFileExtension(path, fileName) : path;
      return await _confirmDownloadConflictsIfNeeded([savePath])
          ? savePath
          : null;
    } on UnimplementedError {
      return _pickDownloadDirectory(fileName);
    } catch (error) {
      if (mounted) {
        _showMessage('无法打开保存位置选择器，请稍后重试。');
      }
      return null;
    }
  }

  Future<_DownloadRoot?> _pickFolderDownloadRoot() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (!await _ensureAndroidDownloadPermissions()) {
        return null;
      }
      final treeUri = await AndroidDownloads.pickFolderUri();
      if (treeUri == null || treeUri.isEmpty) {
        return null;
      }
      return _DownloadRoot.androidTree(treeUri);
    }

    final directory = await getDirectoryPath(
      confirmButtonText: '选择下载位置',
      canCreateDirectories: true,
    );
    if (directory == null) {
      return null;
    }
    return _DownloadRoot.directory(directory);
  }

  Future<bool> _ensureAndroidDownloadPermissions() async {
    final granted = await AndroidDownloads.ensureDownloadPermissions();
    if (!granted && mounted) {
      _showMessage('当前没有下载权限', type: AppNoticeType.warning);
    }
    return granted;
  }

  String _downloadTargetPath(_DownloadRoot root, String relativePath) {
    switch (root) {
      case _DownloadRootDirectory(:final path):
        return _joinLocalPath(path, relativePath);
      case _DownloadRootAndroidTree(:final treeUri):
        return AndroidDownloads.targetPath(
          treeUri: treeUri,
          relativePath: relativePath,
        );
    }
  }

  Future<bool> _confirmDownloadConflictsIfNeeded(
    Iterable<String> targetPaths,
  ) async {
    if (!mounted) {
      return false;
    }
    bool hasConflict;
    try {
      hasConflict = false;
      for (final path in targetPaths) {
        if (await _downloadTargetExists(path)) {
          hasConflict = true;
          break;
        }
      }
    } catch (_) {
      if (mounted) {
        _showMessage('无法检查下载位置，请稍后重试', type: AppNoticeType.error);
      }
      return false;
    }
    if (!hasConflict) {
      return true;
    }
    if (!mounted) {
      return false;
    }
    return showAppConfirmation(
      context,
      title: '命名冲突',
      message: '目标文件夹中已有同名项目。要继续下载并覆盖原项目吗？',
      confirmLabel: '覆盖',
    );
  }

  Future<bool> _downloadTargetExists(String path) async {
    if (AndroidDownloads.isTargetPath(path)) {
      return AndroidDownloads.exists(path);
    }
    return await FileSystemEntity.type(path) != FileSystemEntityType.notFound;
  }

  Future<String?> _pickDownloadDirectory(String fileName) async {
    try {
      final directory = await getDirectoryPath(
        confirmButtonText: '选择下载位置',
        canCreateDirectories: true,
      );
      if (directory == null) {
        return null;
      }
      final normalized = directory.replaceAll(RegExp(r'[\\/]+$'), '');
      final separator = normalized.contains('\\') ? '\\' : '/';
      final savePath = '$normalized$separator$fileName';
      return await _confirmDownloadConflictsIfNeeded([savePath])
          ? savePath
          : null;
    } on UnimplementedError {
      if (mounted) {
      _showMessage('当前平台暂不支持选择下载位置');
      }
      return null;
    } catch (error) {
      if (mounted) {
        _showMessage('无法选择下载位置，请稍后重试');
      }
      return null;
    }
  }

  Future<String?> _pickBatchDownloadPath(List<FileNode> nodes) async {
    try {
      final saveLocation = await getSaveLocation(
        suggestedName: _batchArchiveName(nodes),
        confirmButtonText: '下载',
        canCreateDirectories: true,
      );
      final savePath = saveLocation?.path;
      if (savePath == null) {
        return null;
      }
      return await _confirmDownloadConflictsIfNeeded([savePath])
          ? savePath
          : null;
    } on UnimplementedError {
      final directory = await getDirectoryPath(
        confirmButtonText: '选择下载位置',
        canCreateDirectories: true,
      );
      if (directory == null) {
        return null;
      }
      final normalized = directory.replaceAll(RegExp(r'[\\/]+$'), '');
      final separator = normalized.contains('\\') ? '\\' : '/';
      final savePath = '$normalized$separator${_batchArchiveName(nodes)}';
      return await _confirmDownloadConflictsIfNeeded([savePath])
          ? savePath
          : null;
    } catch (error) {
      if (mounted) {
        _showMessage('无法选择下载位置，请稍后重试');
      }
      return null;
    }
  }

  Future<void> _deleteNodes(List<FileNode> nodes) async {
    if (nodes.isEmpty) {
      return;
    }
    if (!_canRunBatch(nodes)) {
      return;
    }
    final confirmed = await showAppConfirmation(
      context,
      title: '删除项目',
      message: _deleteConfirmationMessage(nodes),
      confirmLabel: '删除',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      final result = await DependenciesScope.of(
        context,
      ).apiClient.moveToRecycleBinBatch(nodes.map((node) => node.id).toList());
      if (!mounted) {
        return;
      }
      DependenciesScope.of(context).transferTaskEvents.markChanged();
      _showBatchActionNotice('删除', result);
      _reload();
    } catch (error) {
      if (mounted) {
        _showMessage(
          normalizeApiError(error).message,
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _rename(FileNode node) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initialName: node.name),
    );
    if (name == null || name.trim().isEmpty || !mounted) {
      return;
    }
    final nameError = requiredTextError(name, label: '名称');
    if (nameError != null) {
      _showMessage(nameError);
      return;
    }
    try {
      await DependenciesScope.of(
        context,
      ).apiClient.renameFile(node.id, name.trim());
      if (mounted) {
        _reload();
      }
    } catch (error) {
      if (mounted) {
        final apiError = normalizeApiError(error);
        _showMessage(
          apiError.code == 'name_conflict' ? '名称已存在' : apiError.message,
          type: apiError.code == 'name_conflict'
              ? AppNoticeType.warning
              : AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _moveNodes(List<FileNode> nodes) async {
    if (nodes.isEmpty) {
      return;
    }
    if (!_canRunBatch(nodes)) {
      return;
    }
    final targetId = await _selectTargetFolder(
      title: '移动到',
      excludedFolderIds: _folderIds(nodes),
    );
    if (targetId == null || !mounted) {
      return;
    }
    try {
      final result = await DependenciesScope.of(context).apiClient
          .moveFilesBatch(
            fileIds: nodes.map((node) => node.id).toList(),
            parentId: _rootTargetToParentId(targetId),
          );
      if (mounted) {
        _showBatchActionNotice('移动', result);
        _reload();
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          normalizeApiError(error).message,
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<void> _copyNodes(List<FileNode> nodes) async {
    if (nodes.isEmpty) {
      return;
    }
    if (!_canRunBatch(nodes)) {
      return;
    }
    final targetId = await _selectTargetFolder(
      title: '复制到',
      excludedFolderIds: _folderIds(nodes),
    );
    if (targetId == null || !mounted) {
      return;
    }
    try {
      final result = await DependenciesScope.of(context).apiClient
          .copyFilesBatch(
            fileIds: nodes.map((node) => node.id).toList(),
            parentId: _rootTargetToParentId(targetId),
          );
      if (mounted) {
        _showBatchActionNotice('复制', result);
        _reload();
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          normalizeApiError(error).message,
          type: AppNoticeType.error,
        );
      }
    }
  }

  Future<String?> _selectTargetFolder({
    required String title,
    Set<String> excludedFolderIds = const <String>{},
  }) {
    return showFolderPickerDialog(
      context,
      title: title,
      excludedFolderIds: excludedFolderIds,
      loadFolders: (parentId) => DependenciesScope.of(
        context,
      ).apiClient.files(type: FileNodeType.folder, parentId: parentId),
    );
  }

  String? _rootTargetToParentId(String targetId) {
    return folderPickerTargetToParentId(targetId);
  }

  Set<String> _folderIds(List<FileNode> nodes) {
    return nodes
        .where((node) => node.type == FileNodeType.folder)
        .map((node) => node.id)
        .toSet();
  }

  bool _canRunBatch(List<FileNode> nodes) {
    if (nodes.length <= 10) {
      return true;
    }
    _showMessage('一次最多选择 10 个项目');
    return false;
  }

  String _batchArchiveName(List<FileNode> nodes) {
    if (nodes.length == 1) {
      return '${nodes.single.name}.zip';
    }
    return 'LinkVault-${nodes.length}项.zip';
  }

  String _deleteConfirmationMessage(List<FileNode> nodes) {
    return '要删除选中的项目吗？删除后可在回收站恢复。';
  }

  String _batchActionMessage(String action, BatchFileActionResult result) {
    if (result.failed == 0) {
      return '$action成功：${result.succeeded} 个项目';
    }
    return '$action完成：${result.succeeded} 个成功，${result.failed} 个失败，请稍后重试';
  }

  void _showBatchActionNotice(String action, BatchFileActionResult result) {
    if (result.failed == 0) {
      return;
    }
    _showMessage(
      _batchActionMessage(action, result),
      type: AppNoticeType.error,
    );
  }

  void _showMessage(String message, {AppNoticeType type = AppNoticeType.info}) {
    showAppNotice(context, message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: '存储',
      currentRoute: AppRoute.files,
      body: FixedSimplePage(
        expandedMaxWidth: 1160,
        header: PageIntro(
          title: '存储',
          leadingIcon: Icons.folder_outlined,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '刷新',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '搜索',
                onPressed: _search,
                icon: const Icon(Icons.search),
              ),
              FilledButton.icon(
                onPressed: _uploading ? null : _upload,
                icon: _uploading
                    ? const Icon(Icons.hourglass_empty)
                    : const Icon(Icons.upload_outlined),
                label: const Text('上传'),
              ),
            ],
          ),
        ),
        expandedChild: FutureBuilder<PageResult<FileNode>>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final connectionFailure =
                !loading &&
                snapshot.hasError &&
                isNetworkConnectionFailure(snapshot.error!);
            if (connectionFailure) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showNetworkConnectionFailureSnackBar(context);
              });
            }
            final items = loading || snapshot.hasError
                ? const <FileNode>[]
                : snapshot.data?.items ?? const <FileNode>[];
            return _NodesPanel(
              items: items,
              showEmptyState: !loading && !snapshot.hasError,
              allowMoveCopy: true,
              onCreateFolder: _createFolder,
              onOpenFolder: _openFolder,
              selectedNodeIds: _selectedNodeIds,
              onSelectAll: (selected) => _toggleAllNodes(items, selected),
              onSelectionChanged: _toggleNodeSelection,
              onDownloadSelected: _downloadNodes,
              onDeleteSelected: _deleteNodes,
              onRename: _rename,
              onMoveSelected: _moveNodes,
              onCopySelected: _copyNodes,
            );
          },
        ),
        children: [
          _FolderPathPanel(path: _folderPath, onSelected: _goToFolder),
        ],
      ),
    );
  }
}

class _FolderPathPanel extends StatelessWidget {
  const _FolderPathPanel({required this.path, required this.onSelected});

  final List<_FolderCrumb> path;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SimplePanel(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 7),
      child: _FolderBreadcrumb(path: path, onSelected: onSelected),
    );
  }
}

class _NodesPanel extends StatelessWidget {
  const _NodesPanel({
    required this.items,
    required this.showEmptyState,
    required this.allowMoveCopy,
    required this.onCreateFolder,
    required this.onOpenFolder,
    required this.selectedNodeIds,
    required this.onSelectAll,
    required this.onSelectionChanged,
    required this.onDownloadSelected,
    required this.onDeleteSelected,
    required this.onRename,
    required this.onMoveSelected,
    required this.onCopySelected,
  });

  final List<FileNode> items;
  final bool showEmptyState;
  final bool allowMoveCopy;
  final VoidCallback? onCreateFolder;
  final ValueChanged<FileNode> onOpenFolder;
  final Set<String> selectedNodeIds;
  final ValueChanged<bool> onSelectAll;
  final void Function(FileNode node, bool selected) onSelectionChanged;
  final ValueChanged<List<FileNode>> onDownloadSelected;
  final ValueChanged<List<FileNode>> onDeleteSelected;
  final ValueChanged<FileNode> onRename;
  final ValueChanged<List<FileNode>> onMoveSelected;
  final ValueChanged<List<FileNode>> onCopySelected;

  @override
  Widget build(BuildContext context) {
    final selectedNodes = items
        .where((node) => selectedNodeIds.contains(node.id))
        .toList(growable: false);
    final allSelected =
        items.isNotEmpty && selectedNodes.length == items.length;
    final toolbar = _SelectionToolbar(
      allowMoveCopy: allowMoveCopy,
      selectedNodes: selectedNodes,
      onRename: selectedNodes.length == 1
          ? () => onRename(selectedNodes.single)
          : null,
      onDownload: selectedNodes.isEmpty
          ? null
          : () => onDownloadSelected(selectedNodes),
      onMove: allowMoveCopy && selectedNodes.isNotEmpty
          ? () => onMoveSelected(selectedNodes)
          : null,
      onCopy: allowMoveCopy && selectedNodes.isNotEmpty
          ? () => onCopySelected(selectedNodes)
          : null,
      onDelete: selectedNodes.isEmpty
          ? null
          : () => onDeleteSelected(selectedNodes),
    );
    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SelectAllCheckbox(
          value: items.isEmpty
              ? false
              : (allSelected
                    ? true
                    : (selectedNodes.isNotEmpty ? null : false)),
          onChanged: items.isEmpty
              ? null
              : (value) => onSelectAll(value ?? !allSelected),
        ),
        const SizedBox(width: 12),
        const Expanded(child: SizedBox.shrink()),
        if (onCreateFolder != null) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: '新建文件夹',
            onPressed: onCreateFolder,
            icon: const Icon(Icons.create_new_folder_outlined),
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          ),
        ],
        const SizedBox(width: 4),
        toolbar,
      ],
    );
    final body = items.isEmpty && showEmptyState
        ? const _EmptyState(label: '暂无内容')
        : ListView.separated(
            primary: false,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SectionDivider(),
            itemBuilder: (context, index) {
              final item = items[index];
              return SimpleListRow(
                dense: true,
                icon: item.type == FileNodeType.folder
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
                title: item.name,
                subtitle:
                    '${formatBytes(item.sizeBytes)} · ${formatDateTime(item.updatedAt)}',
                onTap: item.type == FileNodeType.folder
                    ? () => onOpenFolder(item)
                    : null,
                leading: SizedBox.square(
                  dimension: 40,
                  child: Center(
                    child: Checkbox(
                      value: selectedNodeIds.contains(item.id),
                      onChanged: (value) =>
                          onSelectionChanged(item, value ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              );
            },
          );

    return SimplePanel(
      expandChild: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, const SizedBox(height: 14), Expanded(child: body)],
      ),
    );
  }
}

class _SelectAllCheckbox extends StatelessWidget {
  const _SelectAllCheckbox({required this.value, required this.onChanged});

  final bool? value;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '全选',
      child: SizedBox.square(
        dimension: 40,
        child: Center(
          child: Checkbox(
            value: value,
            tristate: true,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ),
    );
  }
}

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.allowMoveCopy,
    required this.selectedNodes,
    required this.onDownload,
    required this.onDelete,
    required this.onRename,
    required this.onMove,
    required this.onCopy,
  });

  final bool allowMoveCopy;
  final List<FileNode> selectedNodes;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onMove;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final hasSelection = selectedNodes.isNotEmpty;
    final renameDisabledBecauseMultiple = selectedNodes.length > 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: renameDisabledBecauseMultiple ? '只能重命名单个项目' : '重命名',
          onPressed: onRename,
          iconSize: 20,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          icon: Icon(
            Icons.drive_file_rename_outline,
            color: renameDisabledBecauseMultiple
                ? Theme.of(context).disabledColor
                : null,
          ),
        ),
        if (allowMoveCopy) ...[
          IconButton(
            tooltip: '移动',
            onPressed: onMove,
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            icon: const Icon(Icons.drive_file_move_outline),
          ),
          IconButton(
            tooltip: '复制',
            onPressed: onCopy,
            iconSize: 20,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
        IconButton(
          tooltip: '下载',
          onPressed: onDownload,
          iconSize: 20,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          icon: const Icon(Icons.download_outlined),
        ),
        IconButton(
          tooltip: '删除',
          onPressed: onDelete,
          iconSize: 20,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          icon: Icon(
            Icons.delete_outline,
            color: hasSelection ? Theme.of(context).colorScheme.error : null,
          ),
        ),
      ],
    );
  }
}

enum _UploadTargetType { file, folder }

class _UploadTarget {
  const _UploadTarget._({
    required this.type,
    required this.path,
    required this.name,
  });

  const _UploadTarget.file({required String path, required String name})
    : this._(type: _UploadTargetType.file, path: path, name: name);

  const _UploadTarget.folder({required String path, required String name})
    : this._(type: _UploadTargetType.folder, path: path, name: name);

  final _UploadTargetType type;
  final String path;
  final String name;
}

class _UploadBatchSummary {
  int files = 0;
  int folders = 0;
  final List<_UploadFailure> failures = [];

  bool get hasSuccess => files > 0 || folders > 0;
}

class _UploadFailure {
  const _UploadFailure(this.name, this.message);

  final String name;
  final String message;
}

class _UploadTargetDialog extends StatefulWidget {
  const _UploadTargetDialog();

  @override
  State<_UploadTargetDialog> createState() => _UploadTargetDialogState();
}

class _UploadTargetDialogState extends State<_UploadTargetDialog> {
  final List<_UploadTarget> _targets = [];
  bool _picking = false;

  Future<void> _addFiles() async {
    await _runPicker(() async {
      if (AndroidUploads.isSupported) {
        final files = await AndroidUploads.pickFiles();
        _addTargets(
          files
              .map(
                (file) => _UploadTarget.file(
                  path: AndroidUploads.targetPath(file),
                  name: file.name,
                ),
              )
              .toList(),
        );
        return;
      }

      final files = await openFiles(confirmButtonText: '选择文件');
      final targets = <_UploadTarget>[];
      for (final file in files) {
        final target = await _targetFromPath(
          file.path,
          fallbackName: file.name,
          fallbackType: _UploadTargetType.file,
        );
        if (target != null) {
          targets.add(target);
        }
      }
      _addTargets(targets);
    });
  }

  Future<void> _addFolders() async {
    await _runPicker(() async {
      final paths = await getDirectoryPaths(
        confirmButtonText: '选择文件夹',
        canCreateDirectories: false,
      );
      final targets = <_UploadTarget>[];
      for (final path in paths.whereType<String>()) {
        final target = await _targetFromPath(
          path,
          fallbackType: _UploadTargetType.folder,
        );
        if (target != null) {
          targets.add(target);
        }
      }
      _addTargets(targets);
    });
  }

  Future<void> _runPicker(Future<void> Function() action) async {
    setState(() {
      _picking = true;
    });
    try {
      await action();
    } on UnimplementedError {
      if (mounted) {
        _showMessage('当前平台暂不支持该选择方式', type: AppNoticeType.warning);
      }
    } catch (error) {
      if (mounted) {
        _showMessage('无法选择上传目标，请稍后重试', type: AppNoticeType.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
        });
      }
    }
  }

  void _addTargets(List<_UploadTarget> targets) {
    if (targets.isEmpty) {
      return;
    }
    setState(() {
      final existing = _targets
          .map((target) => _normalizePath(target.path))
          .toSet();
      for (final target in targets) {
        if (existing.add(_normalizePath(target.path))) {
          _targets.add(target);
        }
      }
    });
  }

  void _removeTarget(int index) {
    setState(() {
      _targets.removeAt(index);
    });
  }

  void _submit() {
    Navigator.of(context).pop(List<_UploadTarget>.unmodifiable(_targets));
  }

  void _showMessage(String message, {AppNoticeType type = AppNoticeType.info}) {
    showAppNotice(context, message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final pickerHeight = (MediaQuery.sizeOf(context).height * 0.46).clamp(
      220.0,
      360.0,
    );

    return AlertDialog(
      title: const Text('上传'),
      content: SizedBox(
        width: double.maxFinite,
        height: pickerHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _picking ? null : _addFiles,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('选择文件'),
                ),
                OutlinedButton.icon(
                  onPressed: _picking ? null : _addFolders,
                  icon: const Icon(Icons.folder_outlined),
                  label: const Text('选择文件夹'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _targets.isEmpty
                  ? const Center(child: Text('还没有选择要上传的项目'))
                  : ListView.separated(
                      itemCount: _targets.length,
                      separatorBuilder: (context, index) =>
                          const SectionDivider(),
                      itemBuilder: (context, index) {
                        final target = _targets[index];
                        return SimpleListRow(
                          dense: true,
                          icon: target.type == _UploadTargetType.folder
                              ? Icons.folder_outlined
                              : Icons.description_outlined,
                          title: target.name,
                          subtitle: target.type == _UploadTargetType.folder
                              ? '文件夹'
                              : '文件',
                          trailing: IconButton(
                            tooltip: '移除',
                            onPressed: _picking
                                ? null
                                : () => _removeTarget(index),
                            icon: const Icon(Icons.close),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _picking ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _targets.isEmpty || _picking ? null : _submit,
          child: const Text('上传'),
        ),
      ],
    );
  }
}

class _SearchDialog extends StatefulWidget {
  const _SearchDialog();

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('搜索文件'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search)),
          inputFormatters: textInputFormatters(),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('搜索'),
        ),
      ],
    );
  }
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog();

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建文件夹'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: appTextMaxLength,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            prefixIcon: Icon(Icons.folder_outlined),
          ),
          inputFormatters: textInputFormatters(),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('创建'),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: appTextMaxLength,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.drive_file_rename_outline),
            labelText: '名称',
          ),
          inputFormatters: textInputFormatters(),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _FolderBreadcrumb extends StatefulWidget {
  const _FolderBreadcrumb({required this.path, required this.onSelected});

  final List<_FolderCrumb> path;
  final ValueChanged<int> onSelected;

  @override
  State<_FolderBreadcrumb> createState() => _FolderBreadcrumbState();
}

class _FolderBreadcrumbState extends State<_FolderBreadcrumb> {
  final ScrollController _controller = ScrollController();
  String? _lastSignature;
  double? _lastWidth;
  bool _pendingAlignmentUpdate = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pathTextStyle = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(fontSize: 18);

    return LayoutBuilder(
      builder: (context, constraints) {
        _scheduleAlignmentUpdate(constraints.maxWidth);
        return ClipRect(
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < widget.path.length; index++) ...[
                  TextButton(
                    onPressed: index == widget.path.length - 1
                        ? null
                        : () => widget.onSelected(index),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      widget.path[index].name,
                      style: pathTextStyle,
                    ),
                  ),
                  if (index != widget.path.length - 1)
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.black,
                      size: 18,
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _scheduleAlignmentUpdate(double width) {
    final signature = _breadcrumbSignature(widget.path);
    if (_lastSignature == signature && _lastWidth == width) {
      return;
    }
    _lastSignature = signature;
    _lastWidth = width;
    if (_pendingAlignmentUpdate) {
      return;
    }
    _pendingAlignmentUpdate = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingAlignmentUpdate = false;
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final position = _controller.position;
      final targetOffset = position.maxScrollExtent > 0
          ? position.maxScrollExtent
          : 0.0;
      if ((_controller.offset - targetOffset).abs() < 0.5) {
        return;
      }
      _controller.jumpTo(targetOffset);
    });
  }
}

String _breadcrumbSignature(List<_FolderCrumb> path) {
  return path.map((crumb) => '${crumb.id}:${crumb.name}').join('|');
}

class _FolderCrumb {
  const _FolderCrumb({required this.id, required this.name});

  final String id;
  final String name;
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(label)),
    );
  }
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  return '${value.toStringAsFixed(2)} ${units[unitIndex]}';
}

String formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

Future<_UploadTarget?> _targetFromPath(
  String path, {
  String? fallbackName,
  required _UploadTargetType fallbackType,
}) async {
  if (path.isEmpty) {
    return null;
  }
  final entityType = await FileSystemEntity.type(path, followLinks: false);
  final name = (fallbackName == null || fallbackName.isEmpty)
      ? _pathBaseName(path)
      : fallbackName;
  switch (entityType) {
    case FileSystemEntityType.file:
      return _UploadTarget.file(path: path, name: name);
    case FileSystemEntityType.directory:
      return _UploadTarget.folder(path: path, name: name);
    case FileSystemEntityType.notFound:
      return fallbackType == _UploadTargetType.folder
          ? _UploadTarget.folder(path: path, name: name)
          : _UploadTarget.file(path: path, name: name);
    case FileSystemEntityType.link:
    case FileSystemEntityType.pipe:
    case FileSystemEntityType.unixDomainSock:
      return null;
  }
  return null;
}

String _pathBaseName(String path) {
  final normalized = path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final slashIndex = normalized.lastIndexOf('/');
  return slashIndex < 0 ? normalized : normalized.substring(slashIndex + 1);
}

String _baseNameWithoutExtension(String path) {
  final baseName = _pathBaseName(path);
  final extension = _extensionFromName(baseName);
  if (extension == null) {
    return baseName;
  }
  return baseName.substring(0, baseName.length - extension.length - 1);
}

String _ensureFileExtension(String path, String sourceFileName) {
  final extension = _extensionFromName(sourceFileName);
  if (extension == null || _extensionFromName(path) != null) {
    return path;
  }
  return '$path.$extension';
}

String _joinLocalPath(String root, String relativePath) {
  final normalizedRoot = root.replaceAll(RegExp(r'[\\/]+$'), '');
  final normalizedRelative = relativePath
      .split(RegExp(r'[\\/]'))
      .where((part) => part.isNotEmpty)
      .join(Platform.pathSeparator);
  return '$normalizedRoot${Platform.pathSeparator}$normalizedRelative';
}

String _joinRelativePath(String parent, String child) {
  final normalizedParent = parent.replaceAll(RegExp(r'[\\/]+$'), '');
  final normalizedChild = child.replaceAll(RegExp(r'^[\\/]+'), '');
  return '$normalizedParent/$normalizedChild';
}

XTypeGroup _acceptedTypeGroupFor(String fileName) {
  final extension = _extensionFromName(fileName);
  if (extension == null) {
    return const XTypeGroup(label: '所有文件');
  }
  return XTypeGroup(label: '.$extension 文件', extensions: [extension]);
}

String? _extensionFromName(String fileName) {
  final slashIndex = fileName.replaceAll('\\', '/').lastIndexOf('/');
  final baseName = slashIndex < 0 ? fileName : fileName.substring(slashIndex + 1);
  final dotIndex = baseName.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == baseName.length - 1) {
    return null;
  }
  return baseName.substring(dotIndex + 1);
}

String _normalizePath(String path) {
  return path
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'/+$'), '')
      .toLowerCase();
}

sealed class _DownloadRoot {
  const _DownloadRoot();

  const factory _DownloadRoot.directory(String path) = _DownloadRootDirectory;

  const factory _DownloadRoot.androidTree(String treeUri) =
      _DownloadRootAndroidTree;
}

class _DownloadRootDirectory extends _DownloadRoot {
  const _DownloadRootDirectory(this.path);

  final String path;
}

class _DownloadRootAndroidTree extends _DownloadRoot {
  const _DownloadRootAndroidTree(this.treeUri);

  final String treeUri;
}
