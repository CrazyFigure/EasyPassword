# EasyPassword 开发规划

> 保存与查看密码的跨平台应用：Android（APK）+ Windows（EXE）
> 仓库：https://github.com/CrazyFigure/EasyPassword

---

## 1. 技术选型

| 项 | 选型 | 理由 |
|---|---|---|
| 跨平台框架 | **Flutter 3.44（Dart）** | 一套代码产出 Android APK 与 Windows EXE；UI 与 Ardot 设计稿契合度高；GitHub Actions 双端构建成熟 |
| 本地存储 | **SQLite（sqflite / sqlite3）** | 结构清晰、支持事务与排序字段，双端通用 |
| 加密 | **AES-256-GCM（cryptography 包）+ PBKDF2** | 字段级加密存储；密钥由应用锁密码经 PBKDF2-HMAC-SHA256 派生；随机 IV + 认证标签 |
| 同步 | **WebDAV + 加密 JSON 快照** | 原生 HTTP 协议，可对接坚果云/Nutstore 等；增量同步基于版本号与修改时间；先落本地再推送 |
| 状态管理 | **Provider** | 轻量、学习成本低、双端一致 |
| 构建发布 | **GitHub Actions** | tag 触发：Android→APK（含签名可配置），Windows→NSIS 安装包 EXE |

## 2. 目录结构

```
lib/
  main.dart                  # 入口：主题、路由、Provider 装配
  core/
    theme.dart               # 浅粉主题 #F48FB1（对齐 Ardot 设计稿）
    constants.dart           # 颜色/间距/字体等设计令牌
    utils.dart               # 通用工具（格式化、排序比较等）
  models/
    password_item.dart       # 网站/App 条目（密码区或 API Key 区）
    account.dart             # 用户账号（用户名/密码/用户级备注）
    api_key.dart             # API Key（单用户下多套）
    settings_model.dart      # 设置项模型
  services/
    database.dart            # SQLite 建库/迁移
    crypto_service.dart      # AES-GCM 加密/解密 + 密钥派生
    password_service.dart    # 密码区 CRUD + 排序 + 批量
    apikey_service.dart      # API Key 区 CRUD + 三级排序 + 批量
    search_service.dart      # 全局搜索（含分区筛选）
    settings_service.dart    # 设置读写（SharedPreferences）
    webdav_service.dart      # WebDAV 同步（增量、加密快照）
    app_lock_service.dart    # 应用锁 + 安全问题
  ui/
    home/home_page.dart      # 主界面：Tab 切换、排序、批量
    home/password_list.dart  # 密码区列表
    home/apikey_list.dart    # API Key 区列表
    detail/password_detail_page.dart   # 密码详情（多账号、拖动排序、浏览器跳转）
    detail/apikey_detail_page.dart     # API Key 详情（三级结构）
    search/search_page.dart  # 全局搜索页
    settings/settings_page.dart        # 设置页
    settings/tab_customize_sheet.dart  # 底部栏自定义
    settings/app_lock_setup.dart       # 应用锁设置
    settings/webdav_setup.dart         # WebDAV 配置
    widgets/...              # 通用组件
```

## 3. 数据模型

```
password_items（条目，按 type 区分功能区）
  id TEXT PK, type TEXT('password'|'apikey'), name TEXT, url TEXT,
  site_note TEXT, sort_order INTEGER, created_at, updated_at, deleted INTEGER

accounts（账号，挂在条目下）
  id TEXT PK, item_id TEXT FK, username TEXT, password_enc TEXT,
  note TEXT, sort_order INTEGER, created_at, updated_at, deleted INTEGER

api_keys（API Key，挂在账号下，仅 apikey 区使用）
  id TEXT PK, account_id TEXT FK, key_enc TEXT, note TEXT,
  sort_order INTEGER, created_at, updated_at, deleted INTEGER

settings（键值存储）
  key TEXT PK, value TEXT
```

- 密码区与 API Key 区通过 `type` 字段物理分离，互不混用。
- 密码/API Key 字段一律 AES-256-GCM 加密后入库（`_enc` 后缀）。

## 4. 加密方案

- 主密钥：`PBKDF2-HMAC-SHA256(应用锁密码, salt, 210000 次) -> 32B`
- 每个字段独立加密：`AES-256-GCM(随机 12B IV + 明文)`，密文存储为 `iv||ciphertext||tag`（Base64）
- 未开启应用锁时：使用随机生成并存于本地的 `device_key` 加密，保证"密码不以明文落盘"
- WebDAV 快照：全库导出为 JSON（字段已加密）→ AES-GCM 整体再加密 → 上传

## 5. 功能清单（对齐需求 1-3）

| 需求 | 实现 |
|---|---|
| 1 密码 CRUD + 备注 | 条目/账号两级表单，密码默认 `*` 展示 |
| 1.1 单条/全部查看 | 条目级 eye 按钮 + 全局"显示全部"开关 |
| 1.2 一网站多套账号 | accounts 一对多 |
| 1.3 拖动排序（两级） | 长按拖动：条目列表、条目内账号列表 |
| 1.4 浏览器跳转 | 二次确认对话框后 `url_launcher` |
| 2 API Key CRUD + 三级结构 | 条目→账号→api_keys 三级，全功能同密码区 |
| 2.1/2.3/2.4 | eye 显示、账号下多 key、三级拖动排序 |
| 3.1 两类分离 | type 分区，底部 Tab（密码/API Key/搜索/设置） |
| 3.2 信息密度 | 列表两行摘要、详情紧凑卡片 |
| 3.3 全局搜索 | 搜索 name/各级备注/用户名/密码/apikey，分区筛选，点击跳转定位 |
| 3.4 批量操作 | 多选后批量删除/导出 |
| 3.5 设置页 | 应用锁（默认关+安全问题恢复）、字体大小（跟随系统）、WebDAV、底部栏开关/排序/默认Tab、主界面排序（名称升序/自定义） |

## 6. 同步方案（对齐需求 4）

- 每次增删改：先写本地库（事务），更新 `updated_at` 与本地 `rev` 版本
- 手动/自动触发同步：
  1. 拉取 WebDAV 远端快照，比对版本号
  2. 将本地自上次同步以来的变更合并（以更新时间晚者胜）
  3. 合并后**先落本地库**，再整体推送加密快照到 WebDAV
- 冲突策略：按 `updated_at` 时间戳 + 记录级 diff 合并，无法判定时保留双方并标记

## 7. 构建发布（对齐需求 6-7）

- GitHub Actions `release.yml`：`on: push: tags: ['v*']`
  - job1 Android：setup flutter → `flutter build apk --release` → 上传 artifact
  - job2 Windows：setup flutter → 安装 VS 工具链 → `flutter build windows` → NSIS 打包 `EasyPassword-Setup-x.y.z.exe` → 上传 release
- 项目地址为空：由我本地初始化仓库、提交全部源码、配置 workflow，推送 `main` 分支

## 8. 任务分解与状态

- [x] 环境检查
- [x] Flutter SDK 安装（3.44.8 stable）
- [x] 项目脚手架（flutter create + 平台配置）
- [x] 数据层：模型 + 数据库 + 加密
- [x] 服务层：CRUD/排序/搜索/批量/同步/应用锁/设置
- [x] UI 层：5 大页面 + 组件
- [x] 单元测试（15 个用例全部通过）+ 静态分析
- [x] GitHub Actions workflow + 仓库文件
- [ ] Windows 本地构建验证（受符号链接权限限制，改由 CI 验证）
- [ ] 推送 GitHub + 触发 CI 构建
- [ ] README + 交付说明

## 9. 已知环境限制

- 本机未开启 Windows"开发者模式"，Flutter 插件符号链接创建失败，
  本地 `flutter build windows` 无法完成；Android APK 需 Android SDK。
- 解决方案：构建产物全部由 GitHub Actions 产出（tag 触发），
  CI 环境（ubuntu-latest / windows-latest）均无此限制。
