# 定制 / 换皮指南

本仓库是 `N3urda/hongguoTV` 的二次定制分支（`custom`），相对上游的改动集中在这里，
全部通过环境变量配置，不用改代码就能换品牌。

---

## 一、品牌配置（4 个环境变量）

| 变量 | 作用 | 默认值 |
|---|---|---|
| `HONGGUOTV_APPLICATION_ID` | 应用包名，决定能否与官方版共存 | `com.hongguotv.custom` |
| `HONGGUOTV_APP_LABEL` | 桌面/设置里显示的应用名 | `红果TV 定制版` |
| `HONGGUOTV_BRAND_SHORT` | 界面左上角品牌短名 | `红果` |
| `HONGGUOTV_BRAND_ACCENT` | 强调色 `#RRGGBB`，选中态、焦点框、按钮全跟着变 | `#2FD3C0` |
| `HONGGUOTV_VERSION_NAME` | 版本名 | `0.9.0-custom` |
| `HONGGUOTV_VERSION_CODE` | 版本号（整数，覆盖安装必须 ≥ 已装） | `9` |
| `HONGGUOTV_CHECK_UPDATES` | 是否检查官方 release，`true`/`false` | `false` |

设置后重新构建即可：

```powershell
$env:HONGGUOTV_APP_LABEL   = "我的影视"
$env:HONGGUOTV_BRAND_SHORT = "我的"
$env:HONGGUOTV_BRAND_ACCENT = "#7C5CFF"
$env:HONGGUOTV_APPLICATION_ID = "com.me.mytv"
cd E:\aiprojects\hongguoTV\tools
.\build-apk.ps1
.\tv-deploy.ps1 -Serial 192.168.31.100:5555 -Package com.me.mytv
```

> 改了 `APPLICATION_ID` 后，`tv-deploy.ps1` 的 `-Package` 要跟着写新包名。

---

## 二、视觉资源在哪

| 资源 | 路径 | 说明 |
|---|---|---|
| 应用图标 | `kotlin-tv/app/src/main/res/drawable/app_icon.xml` | 矢量图，108×108 viewport，直接改 path |
| 电视 Banner | `kotlin-tv/app/src/main/res/drawable/tv_banner.png` | 400×240（Android TV 要求至少 320×180） |
| 主题色 | `kotlin-tv/app/src/main/res/values/styles.xml` | `colorAccent` / `windowBackground`，需与 `BRAND_ACCENT` 保持一致 |
| 界面配色 | `kotlin-tv/app/src/main/kotlin/com/hongguotv/nativeapp/TvStyle.kt` | 所有颜色集中在这里；`selectedTint` / `navTint` 由主色自动混出 |

生成 Banner 的脚本思路（Windows，System.Drawing）：深色渐变底 + 左侧圆角品牌块
（青色圆 + 镂空播放三角）+ 右侧竖色条 + 标题/副标题。改文案记得同步 `HONGGUOTV_APP_LABEL`。

---

## 三、已做的功能改动

### 1. 独立包名 + 关闭官方更新通道
- `applicationId` 与官方 `com.hongguotv.nativeapp` 隔离，可同机共存、互不覆盖
- `BuildConfig.CHECK_UPDATES=false`：`AppUpdater` 不轮询、不发请求；设置页只提示本地构建

### 2. 播放修复（上游 issue #17 / #22）
- 播放集群拒绝签名请求，且共享 `iid/device_id/cdid` 已被标记 → `Code 110001`
- 改为 `Signer.unsigned()` + `VendorConstants.playerDevice`（每进程随机标识）
- 搜索接口仍走签名，未受影响

### 3. 漫剧搜索兜底
- 应用内搜索接口对漫剧返回 HTTP 200 空 body，站点也没有漫剧搜索路由
- 服务端给合法响应时以它为准；接口不可用时退化为漫剧榜单内按标题匹配（100 部，5 分钟缓存）
- 绝不回落成短剧结果（有单测守着）

---

## 四、构建与部署

见 [tools/README.md](tools/README.md)。核心两条命令：

```powershell
.\build-apk.ps1            # 自动找 JDK17 / SDK / Gradle
.\tv-deploy.ps1 -Build     # 打包 + 局域网安装 + 启动
```

## 五、已知问题

- `:core:test` 里 `AppUpdatesTest.verifiedDownloadAtomicallyReplacesOldFile` 在 Windows 上失败
  （临时文件原子替换的路径语义差异），与定制改动无关，上游代码同样失败
- `adb screencap` 抓不到播放中的画面：小米盒子（Amlogic）的视频层不参与截图合成，属正常现象
