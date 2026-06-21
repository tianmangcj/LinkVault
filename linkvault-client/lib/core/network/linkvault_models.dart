class CaptchaChallenge {
  const CaptchaChallenge({
    required this.token,
    required this.originalImageBase64,
    required this.jigsawImageBase64,
    required this.secretKey,
  });

  final String token;
  final String originalImageBase64;
  final String jigsawImageBase64;
  final String secretKey;

  factory CaptchaChallenge.fromJson(Map<String, dynamic> json) {
    return CaptchaChallenge(
      token: json['token'] as String? ?? '',
      originalImageBase64: json['originalImageBase64'] as String? ?? '',
      jigsawImageBase64: json['jigsawImageBase64'] as String? ?? '',
      secretKey: json['secretKey'] as String? ?? '',
    );
  }
}

class CaptchaVerification {
  const CaptchaVerification({required this.captchaVerification});

  final String captchaVerification;

  factory CaptchaVerification.fromJson(Map<String, dynamic> json) {
    return CaptchaVerification(
      captchaVerification: json['captchaVerification'] as String? ?? '',
    );
  }
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiresAt,
    required this.refreshTokenExpiresAt,
    required this.user,
    required this.device,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiresAt;
  final DateTime refreshTokenExpiresAt;
  final UserProfile user;
  final DeviceInfo device;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      accessTokenExpiresAt: DateTime.parse(
        json['accessTokenExpiresAt'] as String,
      ),
      refreshTokenExpiresAt: DateTime.parse(
        json['refreshTokenExpiresAt'] as String,
      ),
      user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
      device: DeviceInfo.fromJson(json['device'] as Map<String, dynamic>),
    );
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    required this.avatarText,
    required this.role,
    required this.createdAt,
    this.email,
    this.avatarImageData,
  });

  final String id;
  final String username;
  final String? email;
  final String displayName;
  final String avatarText;
  final String? avatarImageData;
  final String role;
  final DateTime createdAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      username: json['username'] as String,
      email: json['email'] as String?,
      displayName: json['displayName'] as String,
      avatarText: json['avatarText'] as String,
      avatarImageData: json['avatarImageData'] as String?,
      role: json['role'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.deviceName,
    required this.platform,
    required this.lastSeenAt,
    required this.current,
    this.appVersion,
    this.lastIp,
  });

  final String id;
  final String deviceName;
  final String platform;
  final String? appVersion;
  final String? lastIp;
  final DateTime lastSeenAt;
  final bool current;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String,
      deviceName: json['deviceName'] as String,
      platform: json['platform'] as String,
      appVersion: json['appVersion'] as String?,
      lastIp: json['lastIp'] as String?,
      lastSeenAt: DateTime.parse(json['lastSeenAt'] as String),
      current: json['current'] as bool? ?? false,
    );
  }
}

class QuotaInfo {
  const QuotaInfo({
    required this.totalBytes,
    required this.usedBytes,
    required this.availableBytes,
    required this.usageRatio,
  });

  final int totalBytes;
  final int usedBytes;
  final int availableBytes;
  final double usageRatio;

  factory QuotaInfo.fromJson(Map<String, dynamic> json) {
    return QuotaInfo(
      totalBytes: json['totalBytes'] as int,
      usedBytes: json['usedBytes'] as int,
      availableBytes: json['availableBytes'] as int,
      usageRatio: (json['usageRatio'] as num).toDouble(),
    );
  }
}

class PageResult<T> {
  const PageResult({required this.items, required this.meta});

  final List<T> items;
  final PageMeta meta;

  factory PageResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parseItem,
  ) {
    final items = (json['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(parseItem)
        .toList();
    return PageResult<T>(
      items: items,
      meta: PageMeta.fromJson(json['meta'] as Map<String, dynamic>),
    );
  }
}

class PageMeta {
  const PageMeta({
    required this.page,
    required this.perPage,
    required this.total,
    required this.totalPages,
  });

  final int page;
  final int perPage;
  final int total;
  final int totalPages;

  factory PageMeta.fromJson(Map<String, dynamic> json) {
    return PageMeta(
      page: json['page'] as int,
      perPage: json['perPage'] as int,
      total: json['total'] as int,
      totalPages: json['totalPages'] as int,
    );
  }
}

enum FileNodeType {
  file,
  folder;

  String get queryValue => name;

  static FileNodeType fromJson(String value) {
    return FileNodeType.values.byName(value.toLowerCase());
  }
}

enum FileSearchScope {
  all,
  files,
  folders;

  String get queryValue => name;
}

class FileNode {
  const FileNode({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.mimeType,
    this.sha256,
    this.recycledAt,
  });

  final String id;
  final String? parentId;
  final String name;
  final FileNodeType type;
  final String status;
  final int sizeBytes;
  final String? mimeType;
  final String? sha256;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? recycledAt;

  factory FileNode.fromJson(Map<String, dynamic> json) {
    return FileNode(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      name: json['name'] as String,
      type: FileNodeType.fromJson(json['type'] as String),
      status: json['status'] as String,
      sizeBytes: json['sizeBytes'] as int,
      mimeType: json['mimeType'] as String?,
      sha256: json['sha256'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      recycledAt: json['recycledAt'] == null
          ? null
          : DateTime.parse(json['recycledAt'] as String),
    );
  }
}

class BatchFileActionResult {
  const BatchFileActionResult({
    required this.total,
    required this.succeeded,
    required this.failed,
    required this.items,
  });

  final int total;
  final int succeeded;
  final int failed;
  final List<BatchFileActionItem> items;

  factory BatchFileActionResult.fromJson(Map<String, dynamic> json) {
    return BatchFileActionResult(
      total: json['total'] as int,
      succeeded: json['succeeded'] as int,
      failed: json['failed'] as int,
      items: (json['items'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(BatchFileActionItem.fromJson)
          .toList(),
    );
  }
}

class BatchFileActionItem {
  const BatchFileActionItem({
    required this.fileId,
    required this.success,
    this.name,
    this.node,
    this.errorCode,
    this.errorMessage,
  });

  final String fileId;
  final String? name;
  final bool success;
  final FileNode? node;
  final String? errorCode;
  final String? errorMessage;

  factory BatchFileActionItem.fromJson(Map<String, dynamic> json) {
    final nodeJson = json['node'];
    return BatchFileActionItem(
      fileId: json['fileId'] as String,
      name: json['name'] as String?,
      success: json['success'] as bool? ?? false,
      node: nodeJson is Map<String, dynamic>
          ? FileNode.fromJson(nodeJson)
          : null,
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

enum TransferDirection {
  upload,
  download;

  String get queryValue => name;

  static TransferDirection fromJson(String value) {
    return TransferDirection.values.byName(value.toLowerCase());
  }
}

enum TransferTaskStatus {
  waiting,
  active,
  paused,
  done,
  failed,
  canceled;

  static TransferTaskStatus fromJson(String value) {
    return TransferTaskStatus.values.byName(value.toLowerCase());
  }
}

class TransferTaskInfo {
  const TransferTaskInfo({
    required this.id,
    required this.direction,
    required this.taskType,
    required this.sourceId,
    required this.title,
    required this.totalBytes,
    required this.transferredBytes,
    required this.progress,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.failureReason,
    this.completedAt,
  });

  final String id;
  final TransferDirection direction;
  final String taskType;
  final String sourceId;
  final String title;
  final int totalBytes;
  final int transferredBytes;
  final double progress;
  final TransferTaskStatus status;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  factory TransferTaskInfo.fromJson(Map<String, dynamic> json) {
    return TransferTaskInfo(
      id: json['id'] as String,
      direction: TransferDirection.fromJson(json['direction'] as String),
      taskType: json['taskType'] as String,
      sourceId: json['sourceId'] as String,
      title: json['title'] as String,
      totalBytes: json['totalBytes'] as int,
      transferredBytes: json['transferredBytes'] as int,
      progress: (json['progress'] as num).toDouble(),
      status: TransferTaskStatus.fromJson(json['status'] as String),
      failureReason: json['failureReason'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
    );
  }
}

class PrepareDownloadInfo {
  const PrepareDownloadInfo({
    required this.downloadTaskId,
    required this.fileId,
    required this.fileName,
    required this.sizeBytes,
    required this.url,
    required this.expiresAt,
    required this.headers,
    this.mimeType,
  });

  final String downloadTaskId;
  final String fileId;
  final String fileName;
  final int sizeBytes;
  final String? mimeType;
  final String url;
  final DateTime expiresAt;
  final Map<String, String> headers;

  factory PrepareDownloadInfo.fromJson(Map<String, dynamic> json) {
    return PrepareDownloadInfo(
      downloadTaskId: json['downloadTaskId'] as String,
      fileId: json['fileId'] as String,
      fileName: json['fileName'] as String,
      sizeBytes: json['sizeBytes'] as int,
      mimeType: json['mimeType'] as String?,
      url: json['url'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      headers: (json['headers'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }
}

class UploadTaskInfo {
  const UploadTaskInfo({
    required this.id,
    required this.fileName,
    required this.sizeBytes,
    required this.transferredBytes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String fileName;
  final int sizeBytes;
  final int transferredBytes;
  final TransferTaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  factory UploadTaskInfo.fromJson(Map<String, dynamic> json) {
    return UploadTaskInfo(
      id: json['id'] as String,
      fileName: json['fileName'] as String,
      sizeBytes: json['sizeBytes'] as int,
      transferredBytes: json['transferredBytes'] as int,
      status: TransferTaskStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
    );
  }
}

class DownloadProgress {
  const DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
  });

  final int downloadedBytes;
  final int totalBytes;

  double get fraction {
    if (totalBytes <= 0) {
      return 0;
    }
    return (downloadedBytes / totalBytes).clamp(0, 1).toDouble();
  }
}
