import 'dart:convert';

import 'package:flutter/services.dart';

class AndroidDownloadTarget {
  const AndroidDownloadTarget({
    required this.treeUri,
    required this.relativePath,
  });

  final String treeUri;
  final String relativePath;
}

class AndroidDownloads {
  const AndroidDownloads._();

  static const _channel = MethodChannel('com.linkvault.app/downloads');
  static const _pathPrefix = 'android-tree-download:';
  static const _maxChannelChunkBytes = 64 * 1024;

  static Future<bool> ensureDownloadPermissions() {
    return _channel
        .invokeMethod<bool>('ensureDownloadPermissions')
        .then((value) => value ?? false);
  }

  static Future<String?> pickFolderUri() {
    return _channel.invokeMethod<String>('pickDownloadFolder');
  }

  static String targetPath({
    required String treeUri,
    required String relativePath,
  }) {
    final payload = jsonEncode({
      'treeUri': treeUri,
      'relativePath': relativePath,
    });
    return '$_pathPrefix${Uri.encodeComponent(payload)}';
  }

  static bool isTargetPath(String path) {
    return path.startsWith(_pathPrefix);
  }

  static AndroidDownloadTarget parseTargetPath(String path) {
    final payload = path.substring(_pathPrefix.length);
    final decoded = jsonDecode(Uri.decodeComponent(payload));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('下载目标无效');
    }
    return AndroidDownloadTarget(
      treeUri: decoded['treeUri'] as String,
      relativePath: decoded['relativePath'] as String,
    );
  }

  static Future<void> createFolder(String path) {
    final target = parseTargetPath(path);
    return _channel.invokeMethod<void>('createFolder', {
      'treeUri': target.treeUri,
      'relativePath': target.relativePath,
    });
  }

  static Future<bool> exists(String path) {
    final target = parseTargetPath(path);
    return _channel
        .invokeMethod<bool>('downloadExists', {
          'treeUri': target.treeUri,
          'relativePath': target.relativePath,
        })
        .then((value) => value ?? false);
  }

  static Future<int> downloadFile({
    required String path,
    required Uri url,
    required Map<String, String> headers,
    int? totalBytes,
    int offset = 0,
    bool offsetAlreadyApplied = false,
    void Function(int downloadedBytes)? onProgress,
  }) async {
    final target = parseTargetPath(path);
    final progressChannel = onProgress == null
        ? null
        : 'com.linkvault.app/downloads/progress/${DateTime.now().microsecondsSinceEpoch}';
    MethodChannel? channel;
    if (progressChannel != null) {
      channel = MethodChannel(progressChannel);
      channel.setMethodCallHandler((call) async {
        if (call.method == 'downloadProgress') {
          final bytes = (call.arguments as num?)?.toInt();
          if (bytes != null) {
            onProgress?.call(bytes);
          }
        }
      });
    }
    try {
      final bytes = await _channel.invokeMethod<int>('downloadFile', {
        'treeUri': target.treeUri,
        'relativePath': target.relativePath,
        'url': url.toString(),
        'headers': headers,
        if (totalBytes != null) 'totalBytes': totalBytes,
        'offset': offset,
        'offsetAlreadyApplied': offsetAlreadyApplied,
        if (progressChannel != null) 'progressChannel': progressChannel,
      });
      return bytes ?? 0;
    } finally {
      channel?.setMethodCallHandler(null);
    }
  }

  static Future<String> openDownload(String path, {bool append = false}) {
    final target = parseTargetPath(path);
    return _channel.invokeMethod<String>('openDownload', {
      'treeUri': target.treeUri,
      'relativePath': target.relativePath,
      'append': append,
    }).then((value) {
      if (value == null || value.isEmpty) {
        throw PlatformException(
          code: 'open_failed',
          message: '无法打开下载目标',
        );
      }
      return value;
    });
  }

  static Future<void> writeDownloadChunk(
    String sessionId,
    List<int> chunk,
  ) async {
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    if (bytes.length <= _maxChannelChunkBytes) {
      await _writeDownloadChunk(sessionId, bytes);
      return;
    }
    for (
      var offset = 0;
      offset < bytes.length;
      offset += _maxChannelChunkBytes
    ) {
      final chunkEnd = offset + _maxChannelChunkBytes;
      final end = chunkEnd < bytes.length ? chunkEnd : bytes.length;
      await _writeDownloadChunk(
        sessionId,
        Uint8List.sublistView(bytes, offset, end),
      );
    }
  }

  static Future<void> _writeDownloadChunk(String sessionId, Uint8List bytes) {
    return _channel.invokeMethod<void>('writeDownloadChunk', {
      'sessionId': sessionId,
      'bytes': bytes,
    });
  }

  static Future<void> closeDownload(String sessionId) {
    return _channel.invokeMethod<void>('closeDownload', {
      'sessionId': sessionId,
    });
  }

  static Future<void> cancelDownload(String sessionId) {
    return _channel.invokeMethod<void>('cancelDownload', {
      'sessionId': sessionId,
    });
  }

  static Future<void> deleteDownload(String path) {
    final target = parseTargetPath(path);
    return _channel.invokeMethod<void>('deleteDownload', {
      'treeUri': target.treeUri,
      'relativePath': target.relativePath,
    });
  }

  static Future<int> size(String path) {
    final target = parseTargetPath(path);
    return _channel
        .invokeMethod<num>('downloadSize', {
          'treeUri': target.treeUri,
          'relativePath': target.relativePath,
        })
        .then((value) => value?.toInt() ?? 0);
  }
}
