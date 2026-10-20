// SPDX-License-Identifier: GPL-3.0-only
package com.hongguotv.nativeapp

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 轻量落盘日志。
 *
 * logcat 是环形缓冲，电视重启或过一段时间就冲掉了；用户报问题时往往已经抓不到现场。
 * 这里把关键事件同时写进 `files/logs/app.log`，单文件上限 512 KB，
 * 写满后滚动为 `app.1.log`（只保留一份），因此磁盘占用恒定在 1 MB 以内。
 *
 * 抓取方式：`tools/pull-logs.ps1`（debug 包走 `adb shell run-as`，无需 root）。
 * 电视上也能在「设置 → 诊断日志」里直接看最近几行。
 */
object AppLog {
    private const val TAG = "HongguoTV"
    private const val MAX_BYTES = 512L * 1024L
    private val lock = Any()
    private val stamp = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US)
    @Volatile private var dir: File? = null

    fun init(context: Context) {
        if (dir != null) return
        val target = File(context.filesDir, "logs").apply { mkdirs() }
        dir = target
        i("app start label=${BuildConfig.APP_LABEL} version=${BuildConfig.VERSION_NAME}(${BuildConfig.VERSION_CODE}) " +
            "package=${BuildConfig.APPLICATION_ID} updates=${BuildConfig.CHECK_UPDATES} " +
            "sdk=${android.os.Build.VERSION.SDK_INT} model=${android.os.Build.MODEL}")
    }

    fun file(): File? = dir?.let { File(it, "app.log") }

    fun i(message: String) = write("I", message, null)
    fun w(message: String, problem: Throwable? = null) = write("W", message, problem)
    fun e(message: String, problem: Throwable? = null) = write("E", message, problem)

    private fun write(level: String, message: String, problem: Throwable?) {
        val line = buildString {
            append(stamp.format(Date()))
            append(' ').append(level).append(' ').append(message)
            if (problem != null) append(" | ").append(problem.javaClass.simpleName).append(": ").append(problem.message)
        }
        when (level) {
            "E" -> Log.e(TAG, line)
            "W" -> Log.w(TAG, line)
            else -> Log.i(TAG, line)
        }
        val folder = dir ?: return
        synchronized(lock) {
            runCatching {
                val target = File(folder, "app.log")
                if (target.length() > MAX_BYTES) {
                    val backup = File(folder, "app.1.log")
                    runCatching { backup.delete() }
                    runCatching { target.renameTo(backup) }
                }
                target.appendText(line + "\n")
            }
        }
    }

    fun sizeText(): String {
        val target = file() ?: return "不可用"
        val kb = (target.length() + 1023) / 1024
        return "$kb KB"
    }

    /** 设置页用：路径 + 大小 + 最近若干行。 */
    fun report(lines: Int = 16): String {
        val target = file() ?: return "日志目录不可用"
        val tail = runCatching { target.readLines().takeLast(lines).joinToString("\n") }.getOrElse { "读取失败" }
        return "路径：${target.absolutePath}\n大小：${sizeText()}\n\n$tail"
    }
}
