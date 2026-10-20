# 局域网传文件 / 装 APK（告别 U 盘）

三个脚本，都在 `tools/` 下。核心思路：**让电视盒子通过 adb over WiFi 变成一台可远程安装的设备**，
装包就一行命令，不用再拷 U 盘、不用来回插拔。

> **定制版包名**：本仓库已改成 `com.hongguotv.custom`（可同机与官方版共存），
> 因此 `tv-deploy.ps1` 默认 `-Package com.hongguotv.custom`；装官方版时加 `-Package com.hongguotv.nativeapp`。

---

## 方案对比

| 方式 | 适合场景 | 速度 | 电视端要求 |
|---|---|---|---|
| **A. adb over WiFi**（推荐，主力） | 装 APK、调试、抓日志、批量推文件 | 局域网满速 | 开一次 USB 调试 |
| **B. HTTP 文件服务** | 临时传字幕/图片/单个 APK | 局域网满速 | 自带浏览器或下载器 |
| **C. SMB 共享文件夹** | 长期当网络盘用，看片、放文件 | 局域网满速 | 装个文件管理器（X-plore / MiXplorer） |
| **D. LocalSend / Syncthing** | 手机 ↔ 电脑 ↔ 电视 互传，图形界面 | 中 | 侧载一个 App |

真正解决"每次插 U 盘装 APK"的是 **A**。

---

## A. adb over WiFi（一次性配置，之后永久）

> **本机实测记录（2026-10-20）**：小米盒子/电视 `MiTV-AZFP0`，Android 9（API 28），1920x1080，
> 无线 adb 地址 `192.168.31.100:5555`，已成功安装 `com.hongguotv.custom` 并正常运行。

### 1. 电视盒子开调试

**小米盒子 / 小米电视（MIUI TV）**

1. 设置 → 关于（关于本机）→ **连续点「产品型号」7 次** → 提示“已处于开发者模式”
2. 返回 设置 → **账户与安全** → **ADB 调试** → 打开
3. 小米默认开放 5555，**不需要 USB 线**，也不需要 `adb tcpip`

**其他品牌**

- 当贝 / 创维 / 酷开：设置 → 关于 → 连点「版本号」7 次 → 开发者选项 → USB 调试
- 天猫魔盒 / 华为荣耀：同上，个别型号还有一层「远程调试」开关
- 外贸盒子（Amlogic/S905 类）：Settings → About → 连点 Build 7 次 → Developer options → USB debugging
- **Android 8 及以下通用兜底**：若没有“网络调试/ADB 调试”开关，需先用 USB 双公头线连一次电脑执行
  ```powershell
  adb tcpip 5555
  adb connect <电视IP>:5555
  ```
  之后拔线，无线连接长期有效（恢复出厂才失效）。

**首次连接必然要授权**：电视上会弹「是否允许 USB 调试吗」，遥控器勾选**一律允许**再点**确定**。
没点之前 `adb devices` 显示 `unauthorized`，点了才变 `device`。

### 2. 找到电视并连上

```powershell
cd E:\aiprojects\hongguoTV\tools
.\tv-connect.ps1
```

脚本会：
- 先试 `adb mdns services` 自动发现（Android 11+ 无线调试会广播）
- 再扫 `192.168.31.0/24` 的 5555 端口（基于 ARP 邻居表，不暴力全扫）
- 连上后打印型号 / Android 版本 / 分辨率

### 3. 构建 + 装到电视，一条命令

```powershell
.\tv-deploy.ps1 -Build
```

内部流程：`gradlew assembleDebug` → 找最新产物 → `adb install -r`（覆盖安装，**保留收藏和观看记录**）→ 启动应用。

其他用法：

```powershell
# 装指定 APK
.\tv-deploy.ps1 -Apk "E:\aiprojects\hongguoTV\kotlin-tv\app\build\outputs\apk\debug\app-debug.apk"

# 签名冲突时（电视上已有官方版）先卸载再装，会清数据
.\tv-deploy.ps1 -Uninstall -Apk .\app-debug.apk

# 只推文件到电视，不装包
.\tv-deploy.ps1 -PushFile "D:\movie.mkv" -PushTo /sdcard/Download/

# 指定设备（多台电视时）
.\tv-deploy.ps1 -Serial 192.168.31.144 -Apk .\app-debug.apk
```

### 4. 装完还能干的事

```powershell
adb -s 192.168.31.144:5555 shell pm list packages | findstr hongguo
adb -s 192.168.31.144:5555 logcat -s HongguoTV:*          # 看运行日志
adb -s 192.168.31.144:5555 shell screencap -p /sdcard/s.png
adb -s 192.168.31.144:5555 pull /sdcard/s.png .\s.png     # 截图拉回电脑
adb -s 192.168.31.144:5555 shell input keyevent 3         # 模拟按返回/主页
```

---

## B. HTTP 文件服务（不装任何 App）

```powershell
cd E:\aiprojects\hongguoTV\tools
.\lan-share.ps1 -Path E:\aiprojects\hongguoTV\kotlin-tv\app\build\outputs\apk\debug
```

输出形如：

```
  电脑访问:  http://localhost:8090/
  电视访问:  http://192.168.31.215:8090/
```

电视上用浏览器（或"下载管理"类 App）打开电视访问地址，点 APK 下载 → 系统弹出安装。

> 注意：Windows 防火墙首次会弹窗，选"允许专用网络"，否则电视访问不到。
> 如果还是不通，手动放行：
> ```powershell
> New-NetFirewallRule -DisplayName "lan-share 8090" -Direction Inbound -Protocol TCP -LocalPort 8090 -Action Allow -Profile Private
> ```

---

## C. SMB 共享文件夹（长期用最舒服）

**电脑端**：

```powershell
# 建共享目录
New-Item -ItemType Directory -Force E:\share | Out-Null
New-SmbShare -Name share -Path E:\share -FullAccess "$env:USERNAME"
# 看共享地址
Get-SmbShare | Format-Table Name,Path
# 确认网络发现已开
Get-NetFirewallRule -DisplayGroup "文件和打印机共享" | Select-Object DisplayName,Enabled
```

**电视端**：装 `X-plore File Manager`（TV 版遥控器可操作）或 `MiXplorer`，
添加服务器：`smb://192.168.31.215/share`，用户名 `admin`，密码是你的 Windows 登录密码。

之后电视能直接播电脑上的视频文件，也能往里拖 APK 点开安装。

---

## D. LocalSend（图形化，多设备互传）

- 电脑端：`winget install LocalSend.LocalSend`
- 电视端：GitHub 下 `LocalSend` 的 Android APK，用方案 A/B 装一次
- 两边同一 WiFi，自动发现，拖文件点发送；电视端可用遥控器方向键操作

Syncthing 更适合"自动同步某个目录"（比如你的 APK 输出目录），但 TV 端配置略麻烦。

---

## 出问题了怎么取证：`pull-logs.ps1`

App 会把关键事件写进 `/data/data/com.hongguotv.custom/files/logs/app.log`
（单文件 512 KB，写满滚动成 `app.1.log`，磁盘占用恒定 1 MB 以内）。
logcat 是环形缓冲，重启就没了，所以这个落盘日志才是排查主力。

```powershell
cd E:\aiprojects\hongguoTV\tools
.\pull-logs.ps1
```

产物在 `E:\aiprojects\hongguoTV\logs\<时间戳>\`：

| 文件 | 内容 |
|---|---|
| `summary.txt` | **发这个最快**：设备信息 + app.log 最近 40 行 + 所有 E/W 行 + logcat 尾部 |
| `app.log` / `app.1.log` | 完整落盘日志（debug 包走 `adb shell run-as`，不需要 root） |
| `logcat.txt` | 本次 logcat 里 `HongguoTV` 与崩溃相关行 |
| `device.txt` | 型号 / 系统版本 / 安装时间 / versionCode |

电视上也能直接看：**设置 → 诊断日志**，弹窗里有路径、大小和最近 16 行。

记什么：启动信息（版本/包名/是否检查更新）、首页加载耗时、每次列表/搜索请求
（tab、类型、页码、关键词、返回条数）、详情打开、播放就绪/首帧/失败、本机记录加载失败。

## 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| `adb connect` 一直 connecting | 电视没开 USB 调试；或防火墙拦了 5555；或从没执行过 `adb tcpip 5555` |
| 电视 IP 会变 | 路由器里给电视 MAC 绑定固定 IP（DHCP 静态分配），或用 `-Subnet` 让脚本自己找 |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | 电视上是官方版签名，和你构建的不同 → `-Uninstall` 后重装 |
| `INSTALL_FAILED_VERSION_DOWNGRADE` | 装的版本号低于已装版本 → 提高 `HONGGUOTV_VERSION_CODE` 或先卸载 |
| 装完图标不出现 | Android TV 需要 LEANBACK launcher intent；若无，用"应用"列表或 adb `am start` 启动 |
