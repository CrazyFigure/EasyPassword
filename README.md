# EasyPassword 🔐

保存与查看密码的跨平台应用：**Android（APK）+ Windows（EXE）**。
浅粉可爱风格，密码与 AI API Key 两类数据分离管理，本地与 WebDAV 均加密存储。

## ✨ 功能

### 密码管理（常规网站/App）
- 添加 / 查看 / 编辑 / 删除：网站或 App、网站级备注、用户名、密码（加密存储，默认 `*` 展示）、用户级备注
- 查看单个密码按钮 + 展示全部密码开关（1.1）
- 单个网站/App 可存多套用户名 + 密码 + 备注（1.2）
- 拖动排序：网站/App 之间、网站内多套密码之间（1.3）
- 网站支持"在浏览器中打开"（二次确认，1.4）

### AI API Key 管理（独立分区，不与密码混淆）
- 同一套增删改查，另含 **API Key** 与 **API Key 级备注**
- 单个用户下可存多套 API Key（2.3）
- 三级拖动排序：条目 → 用户 → API Key（2.4）
- 查看单个 / 全部密码与 Key（2.1）
- 浏览器打开二次确认（2.5）

### 整体
- 密码区与 API Key 区分开（3.1），信息密度适中（3.2）
- 全局搜索：网站/App、各级备注、用户名、密码、API Key，支持分区筛选（全部/密码/API Key），点击跳转定位（3.3）
- 列表批量选择删除（3.4）
- 设置页（3.5）：
  - 应用锁（默认关闭，可设安全问题恢复密码）
  - 字体大小（默认跟随系统）
  - WebDAV 同步配置
  - 底部栏自定义：开关 密码/API Key/搜索/设置、调整顺序、设置默认主页
  - 主界面排序：默认按名称升序，可切换自定义（长按拖动）

### 安全与同步
- 密码/API Key 字段 AES-256-GCM 加密存储（密钥由应用锁密码 PBKDF2 派生）
- 本地与 WebDAV 均为密文（4）
- 增量同步：先落本地，再推送 WebDAV（4.1）

## 📦 构建

打版本标签即自动构建双端安装包：

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会自动产出：
- `app-release.apk`（Android）
- `EasyPassword-Setup-<版本>.exe`（Windows 安装包）

本地构建：

```bash
# 移动端
flutter build apk --release

# Windows（需开启系统"开发者模式"，否则插件符号链接创建会失败）
flutter build windows --release
```

> 说明：Windows 本地构建依赖 Flutter 插件符号链接，请在
> 设置 → 隐私和安全性 → 开发者选项 中开启"开发人员模式"。
> 若未开启，可直接使用 GitHub Actions 的自动构建产物（CI 环境已启用）。

## 🛠 技术栈

Flutter 3.x · Dart · SQLite（sqflite）· AES-256-GCM（cryptography）· WebDAV（http）· Provider

## 📄 许可

MIT
