/// 数据模型：API Key（挂在单个用户账号下，可多套，需求 2.3）
library;

class ApiKey {
  final String id;
  final String accountId; // 所属账号
  final String keyEnc; // API Key（AES-256-GCM 加密存储）
  final String note; // API Key 级备注
  final int sortOrder; // 账号内拖动排序
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  const ApiKey({
    required this.id,
    required this.accountId,
    required this.keyEnc,
    this.note = '',
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  ApiKey copyWith({
    String? keyEnc,
    String? note,
    int? sortOrder,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return ApiKey(
      id: id,
      accountId: accountId,
      keyEnc: keyEnc ?? this.keyEnc,
      note: note ?? this.note,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  factory ApiKey.fromMap(Map<String, dynamic> map) {
    return ApiKey(
      id: map['id'] as String,
      accountId: map['account_id'] as String,
      keyEnc: (map['key_enc'] as String?) ?? '',
      note: (map['note'] as String?) ?? '',
      sortOrder: (map['sort_order'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      deleted: (map['deleted'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'key_enc': keyEnc,
      'note': note,
      'sort_order': sortOrder,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'deleted': deleted ? 1 : 0,
    };
  }
}
