// SPDX-License-Identifier: GPL-3.0-only
package com.hongguotv.nativeapp

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.Window
import android.widget.*

/** A remote-accessible side panel; selecting a number is the only action that changes episodes. */
class EpisodePanel(
    private val activity: Activity,private val count: Int,private val current: Int,
    private val locate: (Int,View,(Int)->Unit)->Unit,
    private val select: (Int)->Unit,private val closed: ()->Unit
) {
    private val dialog=Dialog(activity)
    private var group=current/20
    private var focused=current
    private fun dp(n: Int)=(n*activity.resources.displayMetrics.density).toInt()
    private fun label(value: String,size: Float=17f)=TextView(activity).apply { text=value; textSize=size; setTextColor(TvStyle.text); setPadding(dp(8),dp(6),dp(8),dp(6)) }
    private fun button(value: String,active: Boolean=false,action: ()->Unit)=label(value,16f).apply {
        id=View.generateViewId(); gravity=Gravity.CENTER; minHeight=dp(46); isFocusable=true; isFocusableInTouchMode=true
        fun paint(focus: Boolean) { setTextColor(if(focus) TvStyle.onAccent else TvStyle.text); background=GradientDrawable().apply { setColor(if(focus) TvStyle.accent else if(active) TvStyle.selectedTint else TvStyle.surface); cornerRadius=dp(6).toFloat() } }
        paint(false); setOnFocusChangeListener { _,hasFocus -> paint(hasFocus) }; setOnClickListener { action() }
    }
    fun show() {
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        dialog.setOnDismissListener { closed() }
        render(); dialog.show()
        dialog.window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            setGravity(Gravity.END or Gravity.CENTER_VERTICAL)
            attributes=attributes.apply { x=(activity.resources.displayMetrics.widthPixels*.05f).toInt() }
            setLayout(minOf(dp(520),(activity.resources.displayMetrics.widthPixels*.8f).toInt()),(activity.resources.displayMetrics.heightPixels*.9f).toInt())
        }
    }
    fun dismiss()=dialog.dismiss()
    private fun render(focusGroup: Boolean=false) {
        val content=LinearLayout(activity).apply { orientation=LinearLayout.VERTICAL; setPadding(dp(14),dp(12),dp(14),dp(12)); setBackgroundColor(TvStyle.background) }
        content.addView(label("选集  /  正在看第 ${current+1} 集",20f))
        val actions=LinearLayout(activity)
        val close=button("关闭") { dismiss() }
        lateinit var jump: TextView
        jump=button("跳转集数") { locate(focused,jump) { target -> focused=target; group=target/20; render() } }
        listOf(close,jump).forEach { actions.addView(it,LinearLayout.LayoutParams(0,-2,1f).apply { setMargins(dp(3),dp(3),dp(3),dp(3)) }) }
        content.addView(actions)
        val paging=LinearLayout(activity)
        val groupScroll=HorizontalScrollView(activity).apply { isHorizontalScrollBarEnabled=false; addView(paging) }
        val groups=(0..(count-1)/20).map { index ->
            button("${index*20+1}–${minOf((index+1)*20,count)}",index==group) { group=index; focused=group*20; render(true) }.also {
                paging.addView(it,LinearLayout.LayoutParams(dp(112),-2).apply { setMargins(dp(3),dp(3),dp(3),dp(3)) })
            }
        }
        content.addView(groupScroll)
        content.addView(label("第 ${group*20+1}—${minOf((group+1)*20,count)} 集 / 共 $count 集",14f))
        val scroll=ScrollView(activity); val grid=LinearLayout(activity).apply { orientation=LinearLayout.VERTICAL }; scroll.addView(grid)
        content.addView(scroll,LinearLayout.LayoutParams(-1,0,1f))
        val cells=mutableListOf<TextView>()
        (group*20 until minOf((group+1)*20,count)).toList().chunked(5).forEach { indexes ->
            val row=LinearLayout(activity)
            indexes.forEach { index ->
                val cell=button("${index+1}"+(if(index==current) " ●" else ""),index==current) { select(index) }
                val paint=cell.onFocusChangeListener
                cell.setOnFocusChangeListener { view,hasFocus -> paint?.onFocusChange(view,hasFocus); if(hasFocus) focused=index }
                cell.contentDescription="第 ${index+1} 集"+(if(index==current) "，当前播放" else "")
                row.addView(cell,LinearLayout.LayoutParams(0,-2,1f).apply { setMargins(dp(3),dp(3),dp(3),dp(3)) }); cells+=cell
            }
            repeat(5-indexes.size) { row.addView(Space(activity),LinearLayout.LayoutParams(0,1,1f)) }
            grid.addView(row)
        }
        cells.forEachIndexed { i,cell ->
            cell.nextFocusLeftId=cells[if(i%5==0) i else i-1].id
            cell.nextFocusRightId=cells[if(i%5==4 || i==cells.lastIndex) i else i+1].id
            cell.nextFocusUpId=if(i>=5) cells[i-5].id else groups[group].id
            cell.nextFocusDownId=cells[if(i+5<cells.size) i+5 else if(i/5<cells.lastIndex/5) cells.lastIndex else i].id
        }
        groups.forEachIndexed { i,view ->
            view.nextFocusLeftId=groups[(i-1).coerceAtLeast(0)].id; view.nextFocusRightId=groups[(i+1).coerceAtMost(groups.lastIndex)].id
            view.nextFocusUpId=jump.id; view.nextFocusDownId=cells.first().id
        }
        close.nextFocusDownId=groups[group].id; jump.nextFocusDownId=groups[group].id
        close.nextFocusLeftId=close.id; close.nextFocusRightId=jump.id; jump.nextFocusLeftId=close.id; jump.nextFocusRightId=jump.id
        dialog.setContentView(content)
        if(focusGroup) groups[group].requestFocus() else cells[(focused-group*20).coerceIn(0,cells.lastIndex)].requestFocus()
        groupScroll.post { groupScroll.scrollTo((groups[group].left-dp(12)).coerceAtLeast(0),0) }
    }
}
