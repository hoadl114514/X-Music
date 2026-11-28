package io.github.hoadl114514.netease_client

import android.Manifest
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// 继承 AudioServiceActivity，让界面和后台播放服务共用同一个 FlutterEngine。
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermission()
        preferHighRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        preferHighRefreshRate()
    }

    // 不少系统（ColorOS、MIUI 等）默认只给应用 60Hz，要应用自己声明想用高刷新率。
    // 选当前分辨率下刷新率最高的模式；屏幕不支持高刷时就是当前模式，没有影响。
    private fun preferHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        if (window.attributes.preferredDisplayModeId == best.modeId) return
        window.attributes = window.attributes.apply { preferredDisplayModeId = best.modeId }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "notificationsEnabled" -> result.success(notificationsEnabled())
                "openNotificationSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        AudioOutputChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareText" -> {
                    val send = Intent(Intent.ACTION_SEND)
                        .setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                        .putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject"))
                    startActivity(Intent.createChooser(send, call.argument<String>("title")))
                    result.success(null)
                }
                "openUrl" -> {
                    val view = Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")))
                    result.success(
                        try {
                            startActivity(view)
                            true
                        } catch (e: ActivityNotFoundException) {
                            false
                        },
                    )
                }
                "saveImage" -> saveImage(
                    call.argument<ByteArray>("bytes")!!,
                    call.argument<String>("name")!!,
                    call.argument<String>("mime") ?: "image/jpeg",
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    // 保存图片到相册 Pictures/NeteaseClient。Android 10+ 走 MediaStore，不需要权限；
    // 更早的系统要存储权限，没授权就先申请并返回 false，用户授权后再点一次。
    private fun saveImage(bytes: ByteArray, name: String, mime: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 1002)
            result.success(false)
            return
        }
        val main = Handler(Looper.getMainLooper())
        Thread {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, name)
                        put(MediaStore.Images.Media.MIME_TYPE, mime)
                        put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/NeteaseClient")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("无法创建文件")
                    try {
                        contentResolver.openOutputStream(uri)!!.use { it.write(bytes) }
                        values.clear()
                        values.put(MediaStore.Images.Media.IS_PENDING, 0)
                        contentResolver.update(uri, values, null, null)
                    } catch (e: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw e
                    }
                } else {
                    @Suppress("DEPRECATION")
                    val dir = File(
                        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                        "NeteaseClient",
                    )
                    dir.mkdirs()
                    val file = File(dir, name)
                    file.writeBytes(bytes)
                    @Suppress("DEPRECATION")
                    sendBroadcast(Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, android.net.Uri.fromFile(file)))
                }
                main.post { result.success(true) }
            } catch (e: Exception) {
                main.post { result.error("save_failed", e.message, null) }
            }
        }.start()
    }

    private fun notificationsEnabled(): Boolean =
        getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    // Android 13+ 通知权限默认关闭，audio_service 不会主动申请。没有这个权限媒体通知发不出来，
    // HyperOS 等系统的控制中心、锁屏也就看不到播放卡片。没授权就在启动时申请；
    // 用户拒绝两次后系统不再弹窗，只能从设置页的入口跳到系统设置打开。
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) return
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
    }

    private companion object {
        const val CHANNEL = "netease_client/system_media"
        const val SHARE_CHANNEL = "netease_client/share"
    }
}
