// SPDX-License-Identifier: GPL-3.0-only
package com.hongguotv.core

import org.json.JSONObject

object PlaybackQuality {
    val options=listOf(480,720,1080)
    fun normalize(value: Int)=value.takeIf { it in options } ?: 1080
    fun lower(current: Int)=options.lastOrNull { it<current }
}

/** One automatic recovery budget per episode; only an explicit user retry resets it. */
class RecoveryBudget {
    var attempts=0; private set
    val remaining get()=attempts<3
    val delayMillis get()=listOf(1000L,2500L,5000L).getOrNull(attempts)
    fun consume(): Boolean { if(!remaining) return false; attempts++; return true }
    fun reset() { attempts=0 }
}

data class ResumeTarget(val index: Int,val position: Long,val caughtUp: Boolean=false)
object ResumePlayback {
    fun target(episodes: List<String>,episodeId: String?,position: Long,completed: Boolean): ResumeTarget {
        require(episodes.isNotEmpty())
        val index=episodes.indexOf(episodeId)
        if(index<0) return ResumeTarget(0,0)
        return if(completed) ResumeTarget((index+1).coerceAtMost(episodes.lastIndex),0,index==episodes.lastIndex)
            else ResumeTarget(index,position.coerceAtLeast(0))
    }
}

/** Time-based preview, independent of the remote's repeat frequency. Commit on key release. */
object SeekPreview {
    fun offset(heldMillis: Long): Long {
        val elapsed=heldMillis.coerceAtLeast(0)
        return 10_000L+(elapsed-450).coerceAtLeast(0)*10+(elapsed-2_000).coerceAtLeast(0)*10
    }
    fun target(origin: Long,duration: Long,direction: Int,heldMillis: Long)=
        (origin+direction*offset(heldMillis)).coerceIn(0,(duration-500).coerceAtLeast(0))
}

/** Seen count is a high-water mark, so temporary catalog shrinkage is not a new update. */
data class FavoriteUpdate(val total: Int,val seen: Int,val checkedAt: Long) {
    val added get()=(total-seen).coerceAtLeast(0)
    fun observe(count: Int,now: Long,acknowledge: Boolean=false): FavoriteUpdate {
        require(count>0)
        if(now<checkedAt) return this
        return FavoriteUpdate(count,if(acknowledge) maxOf(seen,count) else seen,now)
    }
    fun json()=JSONObject().put("total",total).put("seen",seen).put("checkedAt",checkedAt)
    companion object {
        fun first(count: Int,now: Long): FavoriteUpdate { require(count>0); return FavoriteUpdate(count,count,now) }
        fun decode(value: JSONObject?)=runCatching {
            require(value!=null)
            val total=value.getInt("total"); val seen=value.getInt("seen"); val time=value.getLong("checkedAt")
            require(total>0 && seen>0 && time>=0)
            FavoriteUpdate(total,seen,time)
        }.getOrNull()
    }
}
