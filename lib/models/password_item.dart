/// 数据模型：网站/App 条目（密码区或 API Key 区）
library;

class PasswordItem {
  final String id;
  final String type; // ItemType.password | ItemType.apikey
  final String name; // 网站/App 名
  final String url; // 网站地址（可选）
  final String siteNote; // 网站级备注
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
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  PasswordItem copyWith({
    String? name,
    String? url,
    String? siteNote,
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
      'sort_order': sortOrder,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'deleted': deleted ? 1 : 0,
    };
  }
}
