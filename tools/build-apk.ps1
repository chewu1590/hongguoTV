<#
.SYNOPSIS
    构建 hongguoTV 的 APK，自动处理 JDK 17 / Gradle / SDK 路径。

.DESCRIPTION
    工程要求 JDK 17（AGP 8.11 强制）和 Gradle 8.13+。
    本脚本会依次尝试：JAVA_HOME -> 常见 JDK17 安装路径 -> Android Studio 自带 JBR；
    Gradle 优先用本地完整版（因为国内访问 services.gradle.org 常超时），再回退 gradlew。

.EXAMPLE
    .\build-apk.ps1

.EXAMPLE
    .\build-apk.ps1 -Variant release -VersionName 1.0.0-custom -VersionCode 100
#>
[CmdletBinding()]
param(
    [ValidateSet("debug", "release")]
    [string]$Variant = "debug",
    [string]$VersionName = "",
    [string]$VersionCode = "",
    [string]$GradleCmd = "",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$kotlinDir = Join-Path $repoRoot "kotlin-tv"
if (-not (Test-Path $kotlinDir)) { throw "找不到 kotlin-tv 目录: $kotlinDir" }

# ---- JDK 17 ----
function Resolve-Jdk17 {
    $cands = @()
    if ($env:JAVA_HOME) { $cands += $env:JAVA_HOME }
    $cands += @(
        "D:\Program Files\Java\jdk-17",
        "C:\Program Files\Java\jdk-17",
        "C:\Program Files\Android\Android Studio\jbr",
        "D:\Program Files\Android\Android Studio\jbr"
    )
    foreach ($c in $cands) {
        $javac = Join-Path $c "bin\javac.exe"
        if (Test-Path $javac) {
            $ver = (& $javac -version 2>&1 | Out-String).Trim()
            if ($ver -match "17\.|2[1-9]\.") { return $c }
        }
    }
    throw "找不到 JDK 17+。装一个 JDK 17 并设 JAVA_HOME，或用 Android Studio 自带的 jbr。"
}

$jdk = Resolve-Jdk17
$env:JAVA_HOME = $jdk
$env:Path = "$jdk\bin;$env:Path"
Write-Host "[i] JDK: $jdk" -ForegroundColor DarkGray

# ---- SDK ----
$sdk = $env:ANDROID_HOME
if (-not $sdk -or -not (Test-Path $sdk)) {
    foreach ($c in @("D:\sdk", "$env:LOCALAPPDATA\Android\Sdk")) { if (Test-Path $c) { $sdk = $c; break } }
}
if (-not $sdk) { throw "找不到 Android SDK，设 ANDROID_HOME。" }
$localProps = Join-Path $kotlinDir "local.properties"
$sdkEsc = $sdk.Replace("\", "\\")
"sdk.dir=$sdkEsc" | Set-Content -Path $localProps -Encoding ASCII
Write-Host "[i] SDK: $sdk" -ForegroundColor DarkGray

# ---- Gradle ----
function Resolve-Gradle {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path $Explicit)) { return $Explicit }
    foreach ($c in @("D:\gradle-8.14.3\bin\gradle.bat", "C:\gradle-8.14.3\bin\gradle.bat")) {
        if (Test-Path $c) { return $c }
    }
    # 本地 gradle 版本太老就退回 wrapper
    return (Join-Path $kotlinDir "gradlew.bat")
}

$gradle = Resolve-Gradle -Explicit $GradleCmd
Write-Host "[i] Gradle: $gradle" -ForegroundColor DarkGray

# ---- 版本号 ----
if ($VersionName) { $env:HONGGUOTV_VERSION_NAME = $VersionName }
if ($VersionCode) { $env:HONGGUOTV_VERSION_CODE = $VersionCode }
if ($VersionName) { Write-Host "[i] versionName: $VersionName" -ForegroundColor DarkGray }
if ($VersionCode) { Write-Host "[i] versionCode: $VersionCode" -ForegroundColor DarkGray }

# ---- 构建 ----
$task = if ($Variant -eq "release") { "assembleRelease" } else { "assembleDebug" }
$args = @($task, "--console=plain")
if ($Clean) { $args = @("clean") + $args }

Push-Location $kotlinDir
try {
    Write-Host "[i] 开始构建: $gradle $($args -join ' ')" -ForegroundColor Cyan
    & $gradle @args
    if ($LASTEXITCODE -ne 0) { throw "构建失败（exit $LASTEXITCODE）" }
} finally {
    Pop-Location
}

# ---- 产物 ----
$apk = Get-ChildItem (Join-Path $kotlinDir "app\build\outputs\apk") -Recurse -Filter "*.apk" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "\\$Variant\\" } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $apk) {
    $apk = Get-ChildItem (Join-Path $kotlinDir "app\build\outputs\apk") -Recurse -Filter "*.apk" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if (-not $apk) { throw "构建成功但找不到 apk 产物" }

Write-Host ""
Write-Host "[✓] APK: $($apk.FullName)" -ForegroundColor Green
Write-Host "    大小: $([math]::Round($apk.Length/1MB,2)) MB" -ForegroundColor Green
Write-Host ""
Write-Host "装到电视:  .\tv-deploy.ps1 -Apk `"$($apk.FullName)`"" -ForegroundColor Cyan
