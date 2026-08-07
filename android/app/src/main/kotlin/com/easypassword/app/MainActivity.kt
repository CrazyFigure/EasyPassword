package com.easypassword.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Xml
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channel = "easypassword/system_font"
    private val updaterChannel = "easypassword/updater"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 注册平台通道：字体选择器首次展开时查询 ROM 已安装字体族。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listSystemFonts" -> result.success(listSystemFontFamilies())
                    else -> result.notImplemented()
                }
            }
        // 注册更新通道：把下载好的 APK 交给系统包安装器。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    else -> result.notImplemented()
                }
            }
    }

    // 拉起系统安装器。APK 必须通过 FileProvider 暴露为 content:// URI，
    // Android 7 起直接传 file:// 会抛 FileUriExposedException。
    private fun installApk(path: String?, result: MethodChannel.Result) {
        val apk = path?.let(::File)
        if (apk == null || !apk.exists()) {
            result.error("missing_file", "安装包不存在", null)
            return
        }
        // Android 8 起「安装未知应用」是按应用授权的，未授权时先引导用户去设置页开启，
        // 否则直接 startActivity 会被静默拒绝，用户看不到任何反馈。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        .setData(Uri.parse("package:$packageName"))
                )
            } catch (_: Exception) {
                // 个别 ROM 阉割了该设置页，此时只能提示用户手动开启
            }
            result.error("permission_denied", "需要授权“安装未知应用”后重试", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            result.success(null)
        } catch (e: Exception) {
            result.error("launch_failed", e.message, null)
        }
    }

    // 解析系统与 OEM 字体配置；仅收集具名 family/alias，匿名回退链不作为可选项。
    private fun listSystemFontFamilies(): List<String> {
        val families = linkedSetOf("sans-serif", "serif", "monospace")
        val configFiles = listOf(
            "/system/etc/fonts.xml",
            "/system/etc/system_fonts.xml",
            "/product/etc/fonts_customization.xml",
            "/system_ext/etc/fonts.xml",
            "/vendor/etc/fonts.xml"
        )
        configFiles.map(::File).filter(File::exists).forEach { file ->
            try {
                file.inputStream().use { stream ->
                    val parser = Xml.newPullParser()
                    parser.setInput(stream, "UTF-8")
                    var event = parser.eventType
                    while (event != XmlPullParser.END_DOCUMENT) {
                        if (event == XmlPullParser.START_TAG &&
                            (parser.name == "family" || parser.name == "alias")) {
                            parser.getAttributeValue(null, "name")
                                ?.trim()
                                ?.takeIf(String::isNotEmpty)
                                ?.let(families::add)
                        }
                        event = parser.next()
                    }
                }
            } catch (_: Exception) {
                // 单个 OEM 配置不可读时继续解析其他来源，系统默认字体始终可用。
            }
        }
        return families.sortedWith(compareBy { it.lowercase(Locale.ROOT) })
    }
}
