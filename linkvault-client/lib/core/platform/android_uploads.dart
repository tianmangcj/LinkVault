import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

class AndroidUploadTarget {
  const AndroidUploadTarget({
    required this.contentUri,
    required this.name,
    required this.sizeBytes,
  });

  final String contentUri;
  final String name;
  final int sizeBytes;
}

class AndroidUploadResponse {
  const AndroidUploadResponse({
    required this.statusCode,
    required this.body,
    this.uploadedBytes,
  });

  final int statusCode;
  final String body;
  final int? uploadedBytes;
}

class AndroidUploads {
  const AndroidUploads._();

  static const _channel = MethodChannel('com.linkvault.app/uploads');
  static const _pathPrefix = 'android-content-upload:';

  static bool get isSupported => Platform.isAndroid;

  static Future<List<AndroidUploadTarget>> pickFiles() async {
    if (!isSupported) {
      return const [];
    }
    final files = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'pickUploadFiles',
    );
    return (files ?? const [])
        .map(
          (file) => AndroidUploadTarget(
            contentUri: file['contentUri'] as String? ?? '',
            name: file['name'] as String? ?? 'upload.bin',
            sizeBytes: (file['sizeBytes'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((file) => file.contentUri.isNotEmpty)
        .toList();
  }

  static String targetPath(AndroidUploadTarget target) {
    final payload = jsonEncode({
      'contentUri': target.contentUri,
      'name': target.name,
      'sizeBytes': target.sizeBytes,
    });
    return '$_pathPrefix${Uri.encodeComponent(payload)}';
  }

  static bool isTargetPath(String path) {
    return path.startsWith(_pathPrefix);
  }

  static AndroidUploadTarget parseTargetPath(String path) {
    final payload = path.substring(_pathPrefix.length);
    final decoded = jsonDecode(Uri.decodeComponent(payload));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('上传目标无效');
    }
    return AndroidUploadTarget(
      contentUri: decoded['contentUri'] as String,
      name: decoded['name'] as String? ?? 'upload.bin',
      sizeBytes: decoded['sizeBytes'] as int? ?? 0,
    );
  }

  static Future<AndroidUploadResponse> uploadFile({
    required String path,
    required Uri url,
    required Map<String, String> headers,
    required String fileName,
    required String uploadSessionId,
    int offset = 0,
    void Function(int uploadedBytes)? onProgress,
  }) async {
    final target = parseTargetPath(path);
    final progressChannel = onProgress == null
        ? null
        : 'com.linkvault.app/uploads/progress/${DateTime.now().microsecondsSinceEpoch}';
    MethodChannel? channel;
    if (progressChannel != null) {
      channel = MethodChannel(progressChannel);
      channel.setMethodCallHandler((call) async {
        if (call.method == 'uploadProgress') {
          final bytes = (call.arguments as num?)?.toInt();
          if (bytes != null) {
            onProgress?.call(bytes);
          }
        }
      });
    }
    final Map<String, Object?>? response;
    try {
      response = await _channel.invokeMapMethod<String, Object?>(
        'uploadFile',
        {
          'contentUri': target.contentUri,
          'url': url.toString(),
          'headers': headers,
          'fileName': fileName,
          'uploadSessionId': uploadSessionId,
          'offset': offset,
          if (progressChannel != null) 'progressChannel': progressChannel,
        },
      );
    } finally {
      channel?.setMethodCallHandler(null);
    }
    if (response == null) {
      throw PlatformException(
        code: 'upload_failed',
        message: '上传未返回结果',
      );
    }
    return AndroidUploadResponse(
      statusCode: (response['statusCode'] as num?)?.toInt() ?? 0,
      body: response['body'] as String? ?? '',
      uploadedBytes: (response['uploadedBytes'] as num?)?.toInt(),
    );
  }

  static Future<void> cancelUpload(String uploadSessionId) {
    return _channel.invokeMethod<void>('cancelUpload', {
      'uploadSessionId': uploadSessionId,
    });
  }
}
