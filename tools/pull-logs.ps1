<#
.SYNOPSIS
    从电视盒子拉取应用落盘日志和 logcat，打包成一个目录，方便排查问题。

.DESCRIPTION
    App 会把关键事件写进 /data/data/<包名>/files/logs/app.log（512 KB 滚动一份）。
    debug 包可以走 `adb shell run-as` 直接读，无需 root；release 包只有在有 root 的设备上才能取到。

    产物落在 -OutDir 下：
      app.log        应用落盘日志（完整）
      app.1.log      上一份滚动的日志（存在才拉）
      logcat.txt     本次 logcat 中 HongguoTV / 崩溃相关行
      device.txt     设备与安装信息
      summary.txt    上面几项的摘要，发给别人看这一份就够

.EXAMPLE
    .\pull-logs.ps1

.EXAMPLE
    .\pull-logs.ps1 -Serial 192.168.31.100:5555 -Package com.hongguotv.custom
#>
[CmdletBinding()]
param(
    [string]$Serial = "",
    [string]$Package = "com.hongguotv.custom",
    [string]$OutDir = "",
    [string]$Adb = ""
)

$ErrorActionPreference = "Continue"

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

# 设备
$serials = @((& $adb devices 2>&1 | Out-String) -split "`r?`n" | Where-Object { $_ -match "^\S+\s+device$" } | ForEach-Object { ($_ -split "\s+")[0] })
if ($Serial) {
    if ($serials -notcontains $Serial) { & $adb connect $Serial | Out-Null; Start-Sleep -Seconds 1; $serials = @($serials + $Serial) }
} elseif ($serials.Count -eq 0) {
    throw "没有可用设备：先插 USB 或运行 tv-connect.ps1 -Subnet <网段>"
} else {
    $Serial = $serials[0]
}
$Serial = if ($Serial) { $Serial } else { $serials[0] }

if (-not $OutDir) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) "logs\$stamp"
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host "[i] 设备: $Serial" -ForegroundColor DarkGray
Write-Host "[i] 包名: $Package" -ForegroundColor DarkGray
Write-Host "[i] 输出: $OutDir" -ForegroundColor DarkGray

# 设备信息
$deviceInfo = @(
    "device=$Serial"
    (& $adb -s $Serial shell "getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk" 2>&1) -join "`n"
    (& $adb -s $Serial shell "dumpsys package $Package | grep -E 'versionName|versionCode|firstInstallTime|lastUpdateTime'" 2>&1) -join "`n"
) -join "`n"
$deviceInfo | Set-Content (Join-Path $OutDir "device.txt") -Encoding UTF8

# 落盘日志
$pulled = @()
foreach ($name in @("app.log", "app.1.log")) {
    $content = & $adb -s $Serial exec-out "run-as $Package cat files/logs/$name" 2>&1 | Out-String
    if ($content -match "No such file|run-as: unknown package|not debuggable|Permission denied") {
        Write-Host "[!] 取不到 $name（release 包需要 root，或还没产生日志）" -ForegroundColor Yellow
        continue
    }
    if ($content.Trim()) {
        $content | Set-Content (Join-Path $OutDir $name) -Encoding UTF8 -NoNewline
        $pulled += $name
        Write-Host "[✓] $name  $([math]::Round($content.Length/1KB,1)) KB" -ForegroundColor Green
    }
}

# logcat
$logcat = & $adb -s $Serial logcat -d -v time 2>&1 | Select-String -Pattern "HongguoTV|AndroidRuntime|FATAL|MediaCodec.*error" | Out-String
$logcat | Set-Content (Join-Path $OutDir "logcat.txt") -Encoding UTF8
Write-Host "[✓] logcat.txt  $([math]::Round($logcat.Length/1KB,1)) KB" -ForegroundColor Green

# 摘要
$appLog = if ($pulled -contains "app.log") { Get-Content (Join-Path $OutDir "app.log") } else { @() }
$summary = @()
$summary += "=== 设备 ==="
$summary += $deviceInfo
$summary += ""
$summary += "=== app.log 最近 40 行（共 $($appLog.Count) 行）==="
$summary += ($appLog | Select-Object -Last 40)
$summary += ""
$summary += "=== app.log 中的异常 ==="
$summary += ($appLog | Select-String -Pattern "\s(E|W)\s" | Select-Object -Last 20 | ForEach-Object { $_.Line })
$summary += ""
$summary += "=== logcat 最近 20 行 ==="
$summary += ($logcat -split "`r?`n" | Select-Object -Last 20)
$summary -join "`n" | Set-Content (Join-Path $OutDir "summary.txt") -Encoding UTF8

Write-Host ""
Write-Host "[✓] 完成。把这个文件发出来最快定位问题：" -ForegroundColor Cyan
Write-Host "    $(Join-Path $OutDir 'summary.txt')" -ForegroundColor Cyan
