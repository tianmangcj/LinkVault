import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum LocalTransferKind {
  upload,
  download;

  static LocalTransferKind fromJson(String value) {
    return LocalTransferKind.values.byName(value);
  }
}

class LocalTransferRecord {
  const LocalTransferRecord({
    required this.kind,
    required this.taskId,
    required this.sourceId,
    required this.title,
    required this.localPath,
    required this.totalBytes,
    required this.createdAt,
    required this.updatedAt,
    this.fileId,
    this.parentId,
    this.transferredBytes = 0,
  });

  final LocalTransferKind kind;
  final String taskId;
  final String sourceId;
  final String title;
  final String localPath;
  final int totalBytes;
  final int transferredBytes;
  final String? fileId;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  LocalTransferRecord copyWith({
    String? taskId,
    String? sourceId,
    String? title,
    String? localPath,
    int? totalBytes,
    int? transferredBytes,
    String? fileId,
    String? parentId,
    DateTime? updatedAt,
  }) {
    return LocalTransferRecord(
      kind: kind,
      taskId: taskId ?? this.taskId,
      sourceId: sourceId ?? this.sourceId,
      title: title ?? this.title,
      localPath: localPath ?? this.localPath,
      totalBytes: totalBytes ?? this.totalBytes,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      fileId: fileId ?? this.fileId,
      parentId: parentId ?? this.parentId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'kind': kind.name,
      'taskId': taskId,
      'sourceId': sourceId,
      'title': title,
      'localPath': localPath,
      'totalBytes': totalBytes,
      'transferredBytes': transferredBytes,
      'fileId': fileId,
      'parentId': parentId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory LocalTransferRecord.fromJson(Map<String, dynamic> json) {
    return LocalTransferRecord(
      kind: LocalTransferKind.fromJson(json['kind'] as String),
      taskId: json['taskId'] as String,
      sourceId: json['sourceId'] as String,
      title: json['title'] as String,
      localPath: json['localPath'] as String,
      totalBytes: json['totalBytes'] as int,
      transferredBytes: json['transferredBytes'] as int? ?? 0,
      fileId: json['fileId'] as String?,
      parentId: json['parentId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

abstract interface class TransferResumeStore {
  Future<void> save(LocalTransferRecord record);

  Future<LocalTransferRecord?> readByTaskId(String taskId);

  Future<LocalTransferRecord?> readBySourceId(String sourceId);

  Future<List<LocalTransferRecord>> readAll();

  Future<void> delete(String taskId);

  Future<void> clear();
}

class SecureTransferResumeStore implements TransferResumeStore {
  const SecureTransferResumeStore([
    this._storage = const FlutterSecureStorage(),
  ]);

  static const _key = 'linkvault.transfer_resume_records';

  final FlutterSecureStorage _storage;

  @override
  Future<void> save(LocalTransferRecord record) async {
    final records = await _readMap();
    records[record.taskId] = record;
    await _writeMap(records);
  }

  @override
  Future<LocalTransferRecord?> readByTaskId(String taskId) async {
    return (await _readMap())[taskId];
  }

  @override
  Future<LocalTransferRecord?> readBySourceId(String sourceId) async {
    final records = await _readMap();
    for (final record in records.values) {
      if (record.sourceId == sourceId) {
        return record;
      }
    }
    return null;
  }

  @override
  Future<List<LocalTransferRecord>> readAll() async {
    return (await _readMap()).values.toList(growable: false);
  }

  @override
  Future<void> delete(String taskId) async {
    final records = await _readMap();
    records.remove(taskId);
    await _writeMap(records);
  }

  @override
  Future<void> clear() {
    return _storage.delete(key: _key);
  }

  Future<Map<String, LocalTransferRecord>> _readMap() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return {};
      }
      final records = <String, LocalTransferRecord>{};
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          final record = LocalTransferRecord.fromJson(item);
          records[record.taskId] = record;
        }
      }
      return records;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeMap(Map<String, LocalTransferRecord> records) {
    final encoded = jsonEncode(
      records.values.map((record) => record.toJson()).toList(growable: false),
    );
    return _storage.write(key: _key, value: encoded);
  }
}
