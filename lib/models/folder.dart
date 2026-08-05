/// 数据模型：文件夹（密码区 / API Key 区通用，按 type 物理分离）
library;

class Folder {
  final String id;
  final String type; // ItemType.password | ItemType.apikey
  final String name; // 文件夹名称
  final int? color; // 自定义颜色（ARGB 整数）；null 表示用主题默认色
  final int sortOrder; // 拖动排序序号
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  const Folder({
    required this.id,
    required this.type,
    required this.name,
    this.color,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  /// 复制并覆盖部分字段。
  /// [color] 可空，需区分「不改动」与「恢复默认色」，后者用 [clearColor]。
  Folder copyWith({
    String? name,
    int? color,
    bool clearColor = false,
    int? sortOrder,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return Folder(
      id: id,
      type: type,
      name: name ?? this.name,
      color: clearColor ? null : (color ?? this.color),
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  /// 从数据库行构造
  factory Folder.fromMap(Map<String, dynamic> map) {
    return Folder(
      id: map['id'] as String,
      type: map['type'] as String,
      name: map['name'] as String,
      color: map['color'] as int?,
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
      'color': color,
      'sort_order': sortOrder,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'deleted': deleted ? 1 : 0,
    };
  }
}
