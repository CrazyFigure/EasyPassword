# Android 签名配置说明

## 问题背景

v0.2.1 和 v0.2.2 之前的版本使用了 **debug 签名**发布，且 CI 上每次构建时 debug keystore 都是随机生成的，导致不同版本的 APK 签名不一致。用户在安装新版本时会遇到"签名冲突"错误，无法覆盖安装。

从 v0.2.2 开始，项目已切换到**固定的 release 签名密钥库**，确保所有后续版本都使用同一个证书签名，用户可以正常覆盖升级。

## ⚠️ 重要提示：现有用户必须卸载重装

**如果你已经安装了 v0.2.1 或更早版本，必须先卸载旧版本，再安装 v0.2.2 及以后的版本。**

### 数据备份方案

EasyPassword 支持 WebDAV 同步，卸载前请务必完成备份：

**卸载前（备份到云端）**

1. 打开应用，进入「设置」→「数据同步」→「WebDAV 同步」
2. 打开 WebDAV 总开关，填写服务器地址、账号、密码后保存（支持坚果云、Nextcloud 等）
3. 在「同步方向」中点击「**本地覆盖远端**」，将当前设备的全部数据强制上传
4. 确认状态提示同步成功后，再卸载旧版本

**重装后（从云端恢复）**

1. 安装新版本，进入「设置」→「数据同步」→「WebDAV 同步」
2. 填写**完全相同**的服务器地址与账号密码并保存
3. 在「同步方向」中点击「**远端覆盖本地**」，把云端快照拉回本设备

> 同步内容包含密码、API Key、应用锁与显示设置，均以加密快照传输。
>
> ⚠️ 卸载会清空本地数据库，且该操作不可撤销，请务必先确认「本地覆盖远端」执行成功。

---

## 本地开发签名配置

本地开发时，构建系统会读取 `android/key.properties` 获取签名配置：

```properties
storePassword=你的密钥库密码
keyPassword=你的密钥密码
keyAlias=easypassword
storeFile=upload-keystore.jks
```

该文件已被 `.gitignore` 忽略，不会提交到版本库。

### 本地构建 release APK

如果本地有完整的签名配置，可以直接构建：

```bash
flutter build apk --release --target-platform android-arm64
```

如果缺少签名配置，构建系统会自动回退到 debug 签名并打印警告：

```
警告：未找到 release 签名配置，回退使用 debug 签名，该产物不可用于发布！
```

这种回退行为仅用于支持本地 `flutter run --release` 调试，**切勿将 debug 签名的 APK 对外发布**。

---

## CI 签名配置（GitHub Actions）

CI 环境从 **GitHub Secrets** 读取签名配置，避免将敏感信息提交到代码仓库。

### 需要配置的 Secrets

在 GitHub 仓库的 `Settings` → `Secrets and variables` → `Actions` 中添加以下 4 个 Secret：

| Secret 名称                   | 说明                                      | 示例值                          |
|-------------------------------|-------------------------------------------|---------------------------------|
| `ANDROID_KEYSTORE_BASE64`     | 密钥库文件的 base64 编码                   | `MIIKpAIBAzCCCm4G...`（很长）   |
| `ANDROID_KEYSTORE_PASSWORD`   | 密钥库密码（storePassword）                | `lfH1YWbTZO...`                 |
| `ANDROID_KEY_ALIAS`           | 密钥别名                                   | `easypassword`                  |
| `ANDROID_KEY_PASSWORD`        | 密钥密码（keyPassword，通常与库密码相同）  | `lfH1YWbTZO...`                 |

### 获取 base64 编码的密钥库

在项目根目录执行：

```bash
base64 -w 0 android/app/upload-keystore.jks > keystore.base64.txt
```

**Windows Git Bash** 或 **macOS/Linux** 都可以用这条命令。生成的 `keystore.base64.txt` 内容就是 `ANDROID_KEYSTORE_BASE64` 的值。

⚠️ **密钥库文件和 base64 文本严禁提交到 Git，请妥善保管！**

---

## 签名校验机制

`.github/workflows/release.yml` 中内置了签名指纹硬校验：

```yaml
env:
  EXPECTED_SHA256: '07:F8:BB:97:AE:B5:7F:1C:6B:67:9D:9D:9B:E8:14:46:83:3B:A1:14:A8:42:54:7E:2A:7B:1E:1A:6F:18:44:EB'
```

每次构建后，CI 会用 `apksigner verify --print-certs` 读取 APK 的实际证书指纹，与期望值比对。如果不一致（比如静默回退到了 debug 签名），构建会立即失败并中止发布，杜绝签名不一致的 APK 流出。

### 查看本地密钥库指纹

```bash
keytool -list -v -keystore android/app/upload-keystore.jks -storepass 你的密码 -alias easypassword | grep SHA256
```

输出示例：

```
SHA256: 07:F8:BB:97:AE:B5:7F:1C:6B:67:9D:9D:9B:E8:14:46:83:3B:A1:14:A8:42:54:7E:2A:7B:1E:1A:6F:18:44:EB
```

---

## 更换密钥库（高风险操作）

**除非密钥库泄露或丢失，否则强烈不建议更换密钥库。**

更换密钥库后：

1. 所有现有用户都必须卸载旧版本，重新安装新版本（签名不一致无法覆盖升级）
2. 必须同步更新 GitHub Secrets 中的 4 个值
3. 必须同步更新 `.github/workflows/release.yml` 中的 `EXPECTED_SHA256` 指纹

### 生成新密钥库的命令参考

```bash
keytool -genkeypair \
  -alias easypassword \
  -keyalg RSA -keysize 4096 -validity 10950 \
  -keystore android/app/upload-keystore.jks \
  -storepass "你的新密码" -keypass "你的新密码" \
  -dname "CN=EasyPassword, OU=EasyPassword, O=EasyPassword, L=Unknown, ST=Unknown, C=CN" \
  -storetype JKS
```

---

## 故障排查

### 问题：CI 构建失败，提示"缺少 ANDROID_KEYSTORE_BASE64 Secret"

**原因**：GitHub Secrets 未配置或名称拼写错误。

**解决**：检查 `Settings` → `Secrets and variables` → `Actions`，确保 4 个 Secret 都已添加，名称大小写完全一致。

### 问题：CI 构建成功，但签名校验失败

**原因**：Secrets 中的密钥库与 CI 中的 `EXPECTED_SHA256` 不匹配，或者密钥库密码错误导致回退到了 debug 签名。

**解决**：
1. 检查本地密钥库指纹是否与 `EXPECTED_SHA256` 一致
2. 检查 Secrets 中的密码是否正确（可以用 `keytool -list` 本地验证）
3. 检查 base64 编码是否完整（不应包含换行符）

### 问题：用户安装新版本时提示"签名冲突"

**原因 1**：用户之前安装的是旧的 debug 签名版本（v0.2.1 及之前）。

**解决**：必须卸载旧版本再安装新版本。卸载前先用「本地覆盖远端」把数据备份到 WebDAV，重装后用「远端覆盖本地」恢复（详见上文「数据备份方案」）。

**原因 2**：不同渠道的 APK 使用了不同的签名（比如自己本地 debug 构建 + 官方 release 包混用）。

**解决**：统一使用 GitHub Release 中的官方 APK。

---

## 安全建议

1. **密钥库文件**（`upload-keystore.jks`）和 **base64 文本** 严禁提交到 Git
2. **密钥库密码** 仅保存在 GitHub Secrets 和个人本地安全位置
3. 定期检查 `.gitignore` 是否正确忽略了 `*.jks`、`*.keystore` 和 `key.properties`
4. 如果密钥库泄露，立即生成新密钥库并通知所有用户重新安装

---

**最后更新**：2026-08-06  
**当前密钥库指纹**：`07:F8:BB:97:AE:B5:7F:1C:6B:67:9D:9D:9B:E8:14:46:83:3B:A1:14:A8:42:54:7E:2A:7B:1E:1A:6F:18:44:EB`
