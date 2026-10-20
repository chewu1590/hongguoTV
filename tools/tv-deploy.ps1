<#
.SYNOPSIS
    构建（可选）+ 通过局域网 adb 安装 APK 到电视盒子 + 启动应用。

.DESCRIPTION
    彻底替代 U 盘流程。默认行为：
      1. 复用已连接的 adb 设备；没有就先跑 tv-connect.ps1 自动找设备
      2. -Build 时先跑 kotlin-tv 的 gradle 打包
      3. adb install -r 覆盖安装（保留应用数据）
      4. 启动主 Activity

.EXAMPLE
    .\tv-deploy.ps1 -Build

.EXAMPLE
    .\tv-deploy.ps1 -Apk "E:\aiprojects\hongguoTV\kotlin-tv\app\build\outputs\apk\debug\app-debug.apk"

.EXAMPLE
    # 只推任意文件到电视（不装包）
    .\tv-deploy.ps1 -PushFile "D:\movie.mp4" -PushTo /sdcard/Download/
#>
[CmdletBinding()]
param(
    [string]$Apk = "",
    [switch]$Build,
    [string]$Subnet = "192.168.31",
    [int]$Port = 5555,
    [string]$Serial = "",
    [string]$Package = "com.hongguotv.custom",
    [string]$PushFile = "",
    [string]$PushTo = "/sdcard/Download/",
    [switch]$Uninstall,
    [string]$Adb = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-Adb {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path $Explicit)) { return $Explicit }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @("$env:ANDROID_HOME\platform-tools\adb.exe", "D:\sdk\platform-tools\adb.exe", "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe")) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    throw "找不到 adb.exe，用 -Adb 指定路径。"
}

$adb = Resolve-Adb -Explicit $Adb
& $adb start-server | Out-Null

function Get-OnlineSerials {
    $out = & $adb devices 2>&1 | Out-String
    $list = @($out -split "`r?`n" | Where-Object { $_ -match "^\S+\s+device$" } | ForEach-Object { ($_ -split "\s+")[0] })
    # 逗号防止单元素数组被 PowerShell 拆包成裸字符串
    return ,$list
}

# ---- 设备 ----
$serials = @(Get-OnlineSerials)
if ($Serial) {
    if ($serials -notcontains $Serial) {
        & $adb connect "${Serial}:$Port" | Out-Null
        Start-Sleep -Seconds 1
        $serials = @(Get-OnlineSerials)
    }
}
if ($serials.Count -eq 0) {
    Write-Host "[i] 没有在线设备，尝试自动发现..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "tv-connect.ps1") -Subnet $Subnet -Port $Port -Adb $adb
    $serials = @(Get-OnlineSerials)
    if ($serials.Count -eq 0) { throw "仍然没有可用设备，先确认电视开机且开启了 ADB 调试。" }
}
if (-not $Serial) {
    if ($serials.Count -gt 1) { throw "检测到多个设备: $($serials -join ', ')，用 -Serial 指定一个。" }
    $Serial = $serials[0]
}
Write-Host "[i] 目标设备: $Serial" -ForegroundColor DarkGray

# ---- 只推文件 ----
if ($PushFile) {
    if (-not (Test-Path $PushFile)) { throw "文件不存在: $PushFile" }
    Write-Host "[i] 推送 $PushFile -> $PushTo" -ForegroundColor Cyan
    & $adb -s $Serial push $PushFile $PushTo
    if ($LASTEXITCODE -ne 0) { throw "adb push 失败" }
    Write-Host "[✓] 已推送，电视上用文件管理器在 $PushTo 里找。" -ForegroundColor Green
    exit 0
}

# ---- 构建 ----
if ($Build -and -not $Apk) {
    $kotlinDir = Join-Path $repoRoot "kotlin-tv"
    if (-not (Test-Path $kotlinDir)) { throw "找不到 kotlin-tv 目录" }
    Write-Host "[i] gradle 打包中（首次会比较慢）..." -ForegroundColor Cyan
    Push-Location $kotlinDir
    try {
        $gradlew = if (Test-Path ".\gradlew.bat") { ".\gradlew.bat" } else { "gradle" }
        & $gradlew assembleDebug
        if ($LASTEXITCODE -ne 0) { throw "gradle 构建失败" }
    } finally {
        Pop-Location
    }
    $found = Get-ChildItem (Join-Path $kotlinDir "app\build\outputs\apk") -Recurse -Filter "*.apk" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $found) { throw "构建完成但找不到 apk 产物" }
    $Apk = $found.FullName
}

if (-not $Apk) {
    # 没给 apk 也没 -Build：找最新的产物
    $found = Get-ChildItem $repoRoot -Recurse -Filter "*.apk" -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "\\build\\intermediates\\" } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $found) { throw "没有 apk。用 -Build 先构建，或用 -Apk 指定路径。" }
    $Apk = $found.FullName
    Write-Host "[i] 自动选用最新 apk: $Apk" -ForegroundColor DarkGray
}

if (-not (Test-Path $Apk)) { throw "apk 不存在: $Apk" }

# ---- 卸载（可选，用于签名冲突）----
if ($Uninstall) {
    Write-Host "[i] 卸载旧包 $Package（会清数据）..." -ForegroundColor Yellow
    & $adb -s $Serial uninstall $Package 2>&1 | Out-Host
}

# ---- 安装 ----
$sizeMb = [math]::Round((Get-Item $Apk).Length / 1MB, 2)
Write-Host "[i] 安装 $([System.IO.Path]::GetFileName($Apk)) ($sizeMb MB) ..." -ForegroundColor Cyan
$installOut = & $adb -s $Serial install -r $Apk 2>&1 | Out-String
Write-Host $installOut.Trim()

if ($installOut -notmatch "Success") {
    if ($installOut -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE|signatures do not match|INSTALL_FAILED_ALREADY_EXISTS") {
        Write-Host ""
        Write-Host "[!] 签名冲突：电视上装的官方版和你这个包签名不同。" -ForegroundColor Yellow
        Write-Host "    先卸载再装： .\tv-deploy.ps1 -Uninstall -Apk `"$Apk`"" -ForegroundColor Yellow
    }
    throw "安装失败，见上面的 adb 输出。"
}

# ---- 启动 ----
Write-Host "[i] 启动 $Package ..." -ForegroundColor Cyan
# 定制版 applicationId 与代码 namespace 可以不同，所以要动态解析真正的入口 Activity
$resolve = (& $adb -s $Serial shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER $Package 2>&1 | Out-String)
$component = ($resolve -split "`r?`n" | Where-Object { $_ -match "\S+/\S+" } | Select-Object -Last 1)
if ($component) {
    $component = $component.Trim()
    $startOut = (& $adb -s $Serial shell am start -n $component 2>&1 | Out-String)
    if ($startOut -match "Error|Exception") { $component = "" }
}
if (-not $component) {
    & $adb -s $Serial shell monkey -p $Package 1 2>&1 | Out-Null
}
Write-Host "[✓] 完成：$Package 已在 $Serial 上运行" -ForegroundColor Green
