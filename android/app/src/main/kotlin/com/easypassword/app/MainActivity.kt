package com.easypassword.app

import android.util.Xml
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channel = "easypassword/system_font"

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
