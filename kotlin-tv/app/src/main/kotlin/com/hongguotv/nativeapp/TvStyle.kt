// SPDX-License-Identifier: GPL-3.0-only
package com.hongguotv.nativeapp

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.GradientDrawable

/** Shared native colors and shapes; no blur, bitmap backgrounds or focus animation. */
object TvStyle {
    /** 主色来自构建配置，换品牌只需设置 HONGGUOTV_BRAND_ACCENT */
    val accent= runCatching { Color.parseColor(BuildConfig.BRAND_ACCENT) }.getOrDefault(Color.rgb(47,211,192))
    val background=Color.rgb(8,12,16)
    val surface=Color.rgb(20,29,38)
    val raised=Color.rgb(29,42,54)
    val text=Color.rgb(242,246,249)
    val muted=Color.rgb(147,166,184)
    val outline=Color.rgb(38,53,68)
    /** 选中态底色：主色与背景按比例混合，换品牌色时自动跟随，不用改各处写死的色值 */
    val selectedTint=blend(accent,background,.24f)
    val navTint=blend(accent,background,.16f)
    private fun blend(top: Int,bottom: Int,ratio: Float)=Color.rgb(
        (Color.red(top)*ratio+Color.red(bottom)*(1-ratio)).toInt(),
        (Color.green(top)*ratio+Color.green(bottom)*(1-ratio)).toInt(),
        (Color.blue(top)*ratio+Color.blue(bottom)*(1-ratio)).toInt())
    const val POSTER_ASPECT=.7f
    fun shape(context: Context,color: Int,border: Int=Color.TRANSPARENT,radius: Int=10)=GradientDrawable().apply {
        setColor(color); cornerRadius=radius*context.resources.displayMetrics.density
        setStroke((2*context.resources.displayMetrics.density).toInt(),border)
    }
    fun card(context: Context,focused: Boolean)=shape(context,if(focused) raised else surface,if(focused) accent else Color.TRANSPARENT)
}
