/// 列表行统一封装：主列表里「文件夹」与「网站条目」混排时的通用行模型。
///
/// 自定义排序模式下两者共用一套 sort_order 序号，可以任意交叉排列，
/// 因此需要一个能同时承载两种数据的行类型。
library;

import 'folder.dart';
import 'password_item.dart';

class ListEntry {
  final Folder? folder;
  final PasswordItem? item;

  const ListEntry.ofFolder(Folder this.folder) : item = null;
  const ListEntry.ofItem(PasswordItem this.item) : folder = null;

  bool get isFolder => folder != null;

  /// 行 id（文件夹与条目的 id 空间互相独立，拼前缀避免 Key 冲突）
  String get id => folder?.id ?? item!.id;

  /// 列表 Key 用：跨两张表保证唯一
  String get entryKey => isFolder ? 'folder-${folder!.id}' : 'item-${item!.id}';

  String get name => folder?.name ?? item!.name;

  int get sortOrder => folder?.sortOrder ?? item!.sortOrder;
}
