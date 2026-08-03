/// 数据模型：用户账号（用户名 / 密码 / 用户级备注）
/// 一个 PasswordItem 下可挂多套 Account（需求 1.2 / 2.2）
library;

class Account {
  final String id;
  final String itemId; // 所属条目
  final String username; // 用户名（明文展示）
  final String passwordEnc; // 密码（AES-256-GCM 加密存储）
  final String note; // 用户级备注
  final int sortOrder; // 条目内拖动排序
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  const Account({
    required this.id,
    required this.itemId,
    required this.username,
    required this.passwordEnc,
    this.note = '',
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  Account copyWith({
    String? username,
    String? passwordEnc,
    String? note,
    int? sortOrder,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return Account(
      id: id,
      itemId: itemId,
      username: username ?? this.username,
      passwordEnc: passwordEnc ?? this.passwordEnc,
      note: note ?? this.note,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as String,
      itemId: map['item_id'] as String,
      username: (map['username'] as String?) ?? '',
      passwordEnc: (map['password_enc'] as String?) ?? '',
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
      'item_id': itemId,
      'username': username,
      'password_enc': passwordEnc,
      'note': note,
      'sort_order': sortOrder,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'deleted': deleted ? 1 : 0,
    };
  }
}
