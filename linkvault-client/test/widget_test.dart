import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linkvault_client/app/app.dart';
import 'package:linkvault_client/app/di/app_dependencies.dart';
import 'package:linkvault_client/core/network/linkvault_api_client.dart';
import 'package:linkvault_client/core/network/linkvault_models.dart';
import 'package:linkvault_client/core/network/token_storage.dart';

void main() {
  testWidgets('renders redesigned login page as the first screen', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.text('LinkVault'), findsWidgets);
    expect(find.text('用户名'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
  });

  testWidgets(
    'filters login account to username characters and password to printable non-space text',
    (tester) async {
      await _pumpApp(tester);

      await tester.enterText(find.byType(TextField).at(0), 'demo user\n中文\t!');
      await tester.enterText(find.byType(TextField).at(1), 'pass word\n123中文!');

      expect(_textFieldAt(tester, 0).controller!.text, 'demouser');
      expect(_textFieldAt(tester, 1).controller!.text, 'password123!');
    },
  );

  testWidgets('rejects weak register password in centered dialog', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('创建账号'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'newUser');
    await tester.enterText(find.byType(TextField).at(1), 'abcdefgh');
    await tester.enterText(find.byType(TextField).at(2), 'abcdefgh');
    await tester.tap(find.text('注册'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('密码必须同时包含数字和字母'), findsOneWidget);
  });

  testWidgets('uses bottom navigation on compact workspace width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpApp(tester);
    await _submitLogin(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('存储'), findsWidgets);
  });

  testWidgets('uses navigation rail on expanded workspace width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpApp(tester);
    await _submitLogin(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('存储'), findsWidgets);
  });

  testWidgets('asks for confirmation before deleting selected file', (
    tester,
  ) async {
    final api = _FakeLinkVaultApi(
      fileItems: [
        FileNode(
          id: 'file-1',
          name: 'report.pdf',
          type: FileNodeType.file,
          status: 'active',
          sizeBytes: 128,
          createdAt: DateTime.utc(2026, 1, 1, 8),
          updatedAt: DateTime.utc(2026, 1, 1, 8),
        ),
      ],
    );

    await _pumpApp(tester, apiClient: api);
    await _submitLogin(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('删除项目'), findsOneWidget);
    expect(find.text('要删除选中的项目吗？删除后可在回收站恢复。'), findsOneWidget);
    expect(api.moveToRecycleBinBatchCallCount, 0);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(api.moveToRecycleBinBatchCallCount, 1);
    expect(api.movedToRecycleBinIds, ['file-1']);
  });

  testWidgets('asks for confirmation before logout', (tester) async {
    final api = _FakeLinkVaultApi();

    await _pumpApp(tester, apiClient: api);
    await _submitLogin(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('要退出当前账号吗？下次使用需要重新登录。'), findsOneWidget);
    expect(api.logoutCallCount, 0);

    await tester.tap(find.widgetWithText(FilledButton, '退出'));
    await tester.pumpAndSettle();

    expect(api.logoutCallCount, 1);
    expect(find.text('LinkVault'), findsWidgets);
  });
}

Widget _app({_FakeLinkVaultApi? apiClient}) {
  return LinkVaultApp(
    dependencies: AppDependencies(
      apiBaseUrl: Uri.parse('http://localhost:8080/api/v1'),
      tokenStorage: _MemoryTokenStorage(),
      apiClient: apiClient ?? _FakeLinkVaultApi(),
    ),
  );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  _FakeLinkVaultApi? apiClient,
}) async {
  await tester.pumpWidget(_app(apiClient: apiClient));
  await tester.pump();
  await tester.pump();
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).at(0), 'demo');
  await tester.enterText(find.byType(TextField).at(1), 'password123');
}

TextField _textFieldAt(WidgetTester tester, int index) {
  return tester.widget<TextField>(find.byType(TextField).at(index));
}

Future<void> _submitLogin(WidgetTester tester) async {
  await _login(tester);
  await tester.drag(find.byType(Slider), const Offset(260, 0));
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text('登录'));
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

class _MemoryTokenStorage implements TokenStorage {
  TokenPair? _tokens;

  @override
  Future<void> clear() async {
    _tokens = null;
  }

  @override
  Future<TokenPair?> read() async => _tokens;

  @override
  Future<void> save(TokenPair tokens) async {
    _tokens = tokens;
  }
}

class _FakeLinkVaultApi implements LinkVaultApi {
  _FakeLinkVaultApi({List<FileNode>? fileItems, List<FileNode>? folderItems})
    : fileItems = fileItems ?? const [],
      folderItems = folderItems ?? const [];

  final _now = DateTime.utc(2026, 1, 1, 8);
  final List<FileNode> fileItems;
  final List<FileNode> folderItems;
  int moveToRecycleBinBatchCallCount = 0;
  int logoutCallCount = 0;
  List<String> movedToRecycleBinIds = const [];

  UserProfile get _user => UserProfile(
    id: 'user-1',
    username: 'demo',
    displayName: 'Demo',
    avatarText: 'D',
    role: 'USER',
    createdAt: _now,
  );

  DeviceInfo get _device => DeviceInfo(
    id: 'device-1',
    deviceName: 'Test Device',
    platform: 'WINDOWS',
    appVersion: '1.0',
    lastSeenAt: _now,
    current: true,
  );

  PageResult<T> _emptyPage<T>() {
    return _page(<T>[]);
  }

  PageResult<T> _page<T>(List<T> items) {
    return PageResult<T>(
      items: items,
      meta: PageMeta(page: 1, perPage: 50, total: items.length, totalPages: 1),
    );
  }

  @override
  Future<CaptchaChallenge> captcha() async {
    return const CaptchaChallenge(
      token: 'captcha-1',
      originalImageBase64: '',
      jigsawImageBase64: '',
      secretKey: '',
    );
  }

  @override
  Future<CaptchaVerification> checkCaptcha({
    required String token,
    required String pointJson,
  }) async {
    return const CaptchaVerification(
      captchaVerification: 'captcha-1---{"x":1,"y":5}',
    );
  }

  @override
  Future<AuthSession> login({
    required String account,
    required String password,
    required String captchaVerification,
  }) async {
    return AuthSession(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      accessTokenExpiresAt: _now.add(const Duration(hours: 1)),
      refreshTokenExpiresAt: _now.add(const Duration(days: 30)),
      user: _user,
      device: _device,
    );
  }

  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    required String confirmPassword,
    required String captchaVerification,
  }) {
    return login(
      account: username,
      password: password,
      captchaVerification: captchaVerification,
    );
  }

  @override
  Future<UserProfile> me() async => _user;

  @override
  Future<UserProfile> updateUsername(String username) async {
    return UserProfile(
      id: _user.id,
      username: username,
      displayName: _user.displayName,
      avatarText: _user.avatarText,
      avatarImageData: _user.avatarImageData,
      role: _user.role,
      createdAt: _user.createdAt,
    );
  }

  @override
  Future<UserProfile> updateAvatar(String avatarImageData) async {
    return UserProfile(
      id: _user.id,
      username: _user.username,
      displayName: _user.displayName,
      avatarText: _user.avatarText,
      avatarImageData: avatarImageData,
      role: _user.role,
      createdAt: _user.createdAt,
    );
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<QuotaInfo> quota() async {
    return const QuotaInfo(
      totalBytes: 1024 * 1024 * 1024,
      usedBytes: 0,
      availableBytes: 1024 * 1024 * 1024,
      usageRatio: 0,
    );
  }

  @override
  Future<List<DeviceInfo>> devices() async => [_device];

  @override
  Future<DeviceInfo> reportCurrentDevice() async => _device;

  @override
  Future<void> revokeDevice(String deviceId) async {}

  @override
  Future<PageResult<FileNode>> files({
    FileNodeType? type,
    String? parentId,
    int page = 1,
    int perPage = 50,
  }) async {
    if (parentId != null) {
      return _emptyPage<FileNode>();
    }
    if (type == FileNodeType.folder) {
      return _page<FileNode>(folderItems);
    }
    if (type == FileNodeType.file) {
      return _page<FileNode>(fileItems);
    }
    return _page<FileNode>([...folderItems, ...fileItems]);
  }

  @override
  Future<PageResult<FileNode>> searchFiles({
    required String query,
    required FileSearchScope scope,
    String? parentId,
    int page = 1,
    int perPage = 50,
  }) async {
    return _emptyPage<FileNode>();
  }

  @override
  Future<FileNode> createFolder({
    String? parentId,
    required String name,
  }) async {
    return FileNode(
      id: 'folder-1',
      parentId: parentId,
      name: name,
      type: FileNodeType.folder,
      status: 'active',
      sizeBytes: 0,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  @override
  Future<FileNode> uploadFile({
    required String path,
    required String fileName,
    String? parentId,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    return FileNode(
      id: 'file-1',
      parentId: parentId,
      name: fileName,
      type: FileNodeType.file,
      status: 'active',
      sizeBytes: 128,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  @override
  Future<UploadTaskInfo> initDirectUploadTask({
    required String? parentId,
    required String fileName,
    required int sizeBytes,
    String? mimeType,
  }) async {
    return UploadTaskInfo(
      id: 'upload-1',
      fileName: fileName,
      sizeBytes: sizeBytes,
      transferredBytes: 0,
      status: TransferTaskStatus.active,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  @override
  Future<FileNode> uploadPreparedFile({
    required String uploadTaskId,
    required String path,
    required String fileName,
    int offset = 0,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const DownloadProgress(downloadedBytes: 128, totalBytes: 128),
    );
    return uploadFile(path: path, fileName: fileName);
  }

  @override
  Future<UploadTaskInfo> uploadTask(String uploadTaskId) async {
    return UploadTaskInfo(
      id: uploadTaskId,
      fileName: 'file.txt',
      sizeBytes: 128,
      transferredBytes: 0,
      status: TransferTaskStatus.paused,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  @override
  Future<FileNode> renameFile(String fileId, String name) async {
    return FileNode(
      id: fileId,
      name: name,
      type: FileNodeType.file,
      status: 'active',
      sizeBytes: 128,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  @override
  Future<FileNode> moveFile(String fileId, String? parentId) async {
    return FileNode(
      id: fileId,
      parentId: parentId,
      name: 'moved',
      type: FileNodeType.folder,
      status: 'active',
      sizeBytes: 0,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  @override
  Future<FileNode> copyFile(String fileId, String? parentId) async {
    return FileNode(
      id: 'copy-$fileId',
      parentId: parentId,
      name: 'copied',
      type: FileNodeType.folder,
      status: 'active',
      sizeBytes: 0,
      createdAt: _now,
      updatedAt: _now,
    );
  }

  @override
  Future<void> moveToRecycleBin(String fileId) async {}

  @override
  Future<BatchFileActionResult> moveFilesBatch({
    required List<String> fileIds,
    String? parentId,
  }) async {
    return _batchResult(fileIds);
  }

  @override
  Future<BatchFileActionResult> copyFilesBatch({
    required List<String> fileIds,
    String? parentId,
  }) async {
    return _batchResult(fileIds);
  }

  @override
  Future<BatchFileActionResult> moveToRecycleBinBatch(
    List<String> fileIds,
  ) async {
    moveToRecycleBinBatchCallCount++;
    movedToRecycleBinIds = List<String>.unmodifiable(fileIds);
    return _batchResult(fileIds);
  }

  @override
  Future<PageResult<FileNode>> recycleBin({
    int page = 1,
    int perPage = 50,
  }) async {
    return _emptyPage<FileNode>();
  }

  @override
  Future<FileNode> restoreFile(
    String fileId, {
    bool useOriginalPath = true,
    String? parentId,
  }) async {
    return createFolder(name: 'restored');
  }

  @override
  Future<void> purgeFile(String fileId) async {}

  @override
  Future<void> emptyRecycleBin() async {}

  @override
  Future<PageResult<TransferTaskInfo>> transferTasks({
    required TransferDirection direction,
    int page = 1,
    int perPage = 50,
  }) async {
    return _emptyPage<TransferTaskInfo>();
  }

  @override
  Future<void> pauseTransferTask(String taskId) async {}

  @override
  Future<void> resumeTransferTask(String taskId) async {}

  @override
  Future<void> pauseAllTransferTasks() async {}

  @override
  Future<void> resumeAllTransferTasks() async {}

  @override
  Future<void> cancelTransferTask(String taskId) async {}

  @override
  Future<void> deleteTransferTask(String taskId) async {}

  @override
  Future<void> clearTransferTasks(TransferDirection direction) async {}

  @override
  Future<void> cancelLocalDownload(String downloadTaskId) async {}

  @override
  Future<void> pauseLocalDownload(String downloadTaskId) async {}

  @override
  Future<void> cancelDownloadTask(String downloadTaskId) async {}

  @override
  Future<void> cancelUploadTask(String uploadTaskId) async {}

  @override
  Future<PrepareDownloadInfo> prepareDownload(String fileId) async {
    return PrepareDownloadInfo(
      downloadTaskId: 'download-1',
      fileId: fileId,
      fileName: 'file.txt',
      sizeBytes: 0,
      url: 'http://localhost/download',
      expiresAt: _now.add(const Duration(minutes: 10)),
      headers: const {},
    );
  }

  @override
  Future<PrepareDownloadInfo> resumeDownload(String downloadTaskId) async {
    return prepareDownload('file-1');
  }

  @override
  Future<PrepareDownloadInfo> downloadFile({
    required String fileId,
    required String savePath,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final info = await prepareDownload(fileId);
    onProgress?.call(
      DownloadProgress(
        downloadedBytes: info.sizeBytes,
        totalBytes: info.sizeBytes,
      ),
    );
    return info;
  }

  @override
  Future<PrepareDownloadInfo> downloadPreparedFile({
    required PrepareDownloadInfo info,
    required String savePath,
    int offset = 0,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      DownloadProgress(
        downloadedBytes: info.sizeBytes,
        totalBytes: info.sizeBytes,
      ),
    );
    return info;
  }

  @override
  Future<void> downloadFilesBatch({
    required List<String> fileIds,
    required String savePath,
    int totalBytes = 0,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      DownloadProgress(downloadedBytes: totalBytes, totalBytes: totalBytes),
    );
  }

  @override
  Future<void> logout() async {
    logoutCallCount++;
  }

  @override
  void close() {}

  BatchFileActionResult _batchResult(List<String> fileIds) {
    return BatchFileActionResult(
      total: fileIds.length,
      succeeded: fileIds.length,
      failed: 0,
      items: [
        for (final fileId in fileIds)
          BatchFileActionItem(fileId: fileId, success: true),
      ],
    );
  }
}
