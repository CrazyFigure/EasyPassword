/// 数据模型：网站/App 条目（密码区或 API Key 区）
library;

class PasswordItem {
  final String id;
  final String type; // ItemType.password | ItemType.apikey
  final String name; // 网站/App 名
  final String url; // 网站地址（可选）
  final String siteNote; // 网站级备注
  final String? folderId; // 所属文件夹；null 表示在根目录
  final int sortOrder; // 拖动排序序号
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  const PasswordItem({
    required this.id,
    required this.type,
    required this.name,
    this.url = '',
    this.siteNote = '',
    this.folderId,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  /// 复制并覆盖部分字段。
  /// [folderId] 为可空字段，需要区分「不改动」与「移出文件夹（置为 null）」，
  /// 因此用 [clearFolder] 显式表达后者。
  PasswordItem copyWith({
    String? name,
    String? url,
    String? siteNote,
    String? folderId,
    bool clearFolder = false,
    int? sortOrder,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return PasswordItem(
      id: id,
      type: type,
      name: name ?? this.name,
      url: url ?? this.url,
      siteNote: siteNote ?? this.siteNote,
      folderId: clearFolder ? null : (folderId ?? this.folderId),
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  /// 从数据库行构造
  factory PasswordItem.fromMap(Map<String, dynamic> map) {
    return PasswordItem(
      id: map['id'] as String,
      type: map['type'] as String,
      name: map['name'] as String,
      url: (map['url'] as String?) ?? '',
      siteNote: (map['site_note'] as String?) ?? '',
      folderId: map['folder_id'] as String?,
      sortOrder: (map['sort_order'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      deleted: (map['deleted'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'name': name,
      'url': url,
      'site_note': siteNote,
      'folder_id': folderId,
      'sort_order': sortOrder,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'deleted': deleted ? 1 : 0,
    };
  }
}
