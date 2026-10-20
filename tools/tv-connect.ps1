<#
.SYNOPSIS
    在局域网里找到开启 ADB 调试的电视/盒子，并 adb connect 上去。

.DESCRIPTION
    优先使用 adb mdns 自动发现（Android 11+ 无线调试会广播），
    找不到时回退到 ARP 邻居表 + 端口 5555 探测。
    连接成功后列出设备信息（型号 / Android 版本 / 分辨率）。

.EXAMPLE
    .\tv-connect.ps1

.EXAMPLE
    .\tv-connect.ps1 -Subnet 192.168.31 -Port 5555
#>
[CmdletBinding()]
param(
    [string]$Subnet = "192.168.31",
    [int]$Port = 5555,
    [string]$Adb = ""
)

$ErrorActionPreference = "Continue"

function Resolve-Adb {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path $Explicit)) { return $Explicit }
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "$env:ANDROID_HOME\platform-tools\adb.exe",
        "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "D:\sdk\platform-tools\adb.exe",
        "C:\platform-tools\adb.exe"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    throw "找不到 adb.exe。请安装 platform-tools 或用 -Adb 指定完整路径。"
}

function Test-Port {
    param([string]$Target, [int]$Port, [int]$TimeoutMs = 500)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($Target, $Port, $null, $null)
        if ($async.AsyncWaitHandle.WaitOne($TimeoutMs) -and $client.Connected) { return $true }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

$adb = Resolve-Adb -Explicit $Adb
Write-Host "[i] adb: $adb" -ForegroundColor DarkGray

& $adb start-server | Out-Null

# ---- 1) mDNS 自动发现 ----
Write-Host "[1/2] mDNS 自动发现中..." -ForegroundColor Cyan
$connected = @()
try {
    $mdnsOut = & $adb mdns services 2>&1 | Out-String
    $serviceLines = $mdnsOut -split "`r?`n" | Where-Object { $_ -match "_adb" }
    foreach ($line in $serviceLines) {
        $parts = $line -split "\s+"
        $hostPort = $parts | Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+:\d+$" } | Select-Object -First 1
        if (-not $hostPort) {
            $hostPort = $parts | Where-Object { $_ -match ":\d+$" } | Select-Object -First 1
        }
        if ($hostPort) {
            Write-Host "    mdns: $hostPort" -ForegroundColor Gray
            $out = & $adb connect $hostPort 2>&1 | Out-String
            if ($out -match "connected") { $connected += $hostPort }
        }
    }
} catch {
    Write-Host "    mDNS 不可用（老版 adb 或电视不支持）" -ForegroundColor DarkYellow
}

# ---- 2) ARP + 5555 端口探测 ----
if ($connected.Count -eq 0) {
    Write-Host "[2/2] 扫描 $Subnet.0/24 的 $Port 端口..." -ForegroundColor Cyan
    $neighbors = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -like "$Subnet.*" -and $_.State -in @("Reachable", "Stale", "Delay", "Probe", "Permanent") } |
        Select-Object -ExpandProperty IPAddress -Unique

    $candidates = @($neighbors | Where-Object { $_ -notmatch "\.(1|255)$" })
    Write-Host "    ARP 邻居 $($candidates.Count) 个，逐个探测..." -ForegroundColor Gray

    foreach ($ip in $candidates) {
        if (Test-Port -Target $ip -Port $Port) {
            $target = "${ip}:$Port"
            Write-Host "    命中 $target" -ForegroundColor Green
            $out = & $adb connect $target 2>&1 | Out-String
            Write-Host "    $($out.Trim())" -ForegroundColor Gray
            if ($out -match "connected") { $connected += $target }
        }
    }
}

# ---- 结果 ----
$devices = (& $adb devices -l 2>&1 | Out-String)
Write-Host ""
Write-Host "当前设备列表:" -ForegroundColor Cyan
$devices.Trim() | Write-Host

$online = @($devices -split "`r?`n" | Where-Object { $_ -match "\sdevice\s" })
if ($online.Count -eq 0) {
    Write-Host ""
    Write-Host "没有连上的设备。检查清单：" -ForegroundColor Yellow
    Write-Host "  1. 电视盒子 设置 -> 关于 -> 版本号 连点 7 次，打开开发者选项"
    Write-Host "  2. 开发者选项里打开 'USB 调试'（部分盒子叫 'ADB 调试' / '网络调试'）"
    Write-Host "  3. Android 11+ 用 '无线调试' 配对: adb pair <IP>:<配对端口>"
    Write-Host "  4. 首次连接电视上会弹 '允许 USB 调试吗'，用遥控器点允许"
    Write-Host "  5. Android 8 及以下：先用 USB 线连一次执行 adb tcpip 5555，之后才能无线"
    exit 1
}

foreach ($line in $online) {
    $serial = ($line -split "\s+")[0]
    Write-Host ""
    Write-Host "=== $serial ===" -ForegroundColor Green
    & $adb -s $serial shell "getprop ro.product.model; getprop ro.build.version.release; wm size; ip route" 2>&1 | Write-Host
}
exit 0
