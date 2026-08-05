package com.easypassword.app

import android.util.Xml
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.xmlpull.v1.XmlPullParser
import java.io.File

class MainActivity : FlutterActivity() {
    private val channel = "easypassword/system_font"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 注册平台通道：供 Flutter 侧查询系统默认字体文件字节
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSystemFontBytes" -> result.success(getSystemFontBytes())
                    else -> result.notImplemented()
                }
            }
    }

    // 获取系统默认字体文件字节：先解析 fonts.xml 找到 sans-serif 常规字体路径，再读取文件
    private fun getSystemFontBytes(): ByteArray? {
        return try {
            val path = findDefaultFontPath() ?: return null
            File(path).readBytes()
        } catch (e: Exception) {
            null
        }
    }

    // 解析 /system/etc/fonts.xml，返回默认 sans-serif 常规字体的完整路径
    private fun findDefaultFontPath(): String? {
        // 优先 fonts.xml，备选旧版 system_fonts.xml
        val xmlFile = File("/system/etc/fonts.xml").takeIf { it.exists() }
            ?: File("/system/etc/system_fonts.xml").takeIf { it.exists() }
            ?: return null
        return try {
            val parser = Xml.newPullParser()
            parser.setInput(xmlFile.inputStream(), "UTF-8")
            var event = parser.eventType
            var inSansSerif = false
            while (event != XmlPullParser.END_DOCUMENT) {
                if (event == XmlPullParser.START_TAG) {
                    when (parser.name) {
                        "family" -> {
                            // name="sans-serif" 即系统默认字体族（OEM 会替换其指向的字体文件）
                            val name = parser.getAttributeValue(null, "name")
                            inSansSerif = name == "sans-serif"
                        }
                        "font" -> {
                            if (inSansSerif) {
                                // 取 weight=400 style=normal 的常规字体
                                val weight = parser.getAttributeValue(null, "weight")
                                val style = parser.getAttributeValue(null, "style") ?: "normal"
                                if ((weight == null || weight == "400") && style == "normal") {
                                    val fileName = parser.nextText()
                                    val fontFile = File("/system/fonts/$fileName")
                                    if (fontFile.exists()) return fontFile.absolutePath
                                }
                            }
                        }
                    }
                }
                event = parser.next()
            }
            // 兜底：直接尝试 Roboto-Regular.ttf
            val fallback = File("/system/fonts/Roboto-Regular.ttf")
            if (fallback.exists()) fallback.absolutePath else null
        } catch (e: Exception) {
            null
        }
    }
}
