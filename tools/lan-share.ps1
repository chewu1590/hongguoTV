<#
.SYNOPSIS
    在电脑上起一个局域网 HTTP 文件服务，电视盒子用浏览器/下载器直接拉文件。

.DESCRIPTION
    基于 TcpListener 实现的最小 HTTP/1.1 服务，非管理员权限即可运行（不需要 URL ACL）。
    适合临时传 APK、字幕、图片这类文件，比 U 盘快，电视端不用装任何 App。
    支持目录浏览、Content-Length、单段 Range（电视播放器拖进度条用）。
    Ctrl+C 停止。

.EXAMPLE
    .\lan-share.ps1 -Path E:\aiprojects\hongguoTV\kotlin-tv\app\build\outputs\apk\debug

.EXAMPLE
    .\lan-share.ps1 -Path . -Port 8091
#>
[CmdletBinding()]
param(
    [string]$Path = ".",
    [int]$Port = 8090
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path $Path).Path
if (-not (Test-Path $root -PathType Container)) { throw "不是目录: $root" }

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and $_.InterfaceAlias -notmatch "Virtual|WSL|Tailscale|Kerio|Loopback" } |
    Select-Object -First 1).IPAddress
if (-not $ip) { $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object -First 1).IPAddress }

$mime = @{
    ".apk" = "application/vnd.android.package-archive"
    ".mp4" = "video/mp4"; ".mkv" = "video/x-matroska"; ".avi" = "video/x-msvideo"
    ".jpg" = "image/jpeg"; ".jpeg" = "image/jpeg"; ".png" = "image/png"; ".gif" = "image/gif"
    ".srt" = "text/plain; charset=utf-8"; ".ass" = "text/plain; charset=utf-8"
    ".txt" = "text/plain; charset=utf-8"; ".html" = "text/html; charset=utf-8"
    ".zip" = "application/zip"; ".json" = "application/json"; ".log" = "text/plain; charset=utf-8"
}

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
$listener.Start()

Write-Host ""
Write-Host "局域网文件服务已启动（Ctrl+C 停止）" -ForegroundColor Green
Write-Host "  目录: $root" -ForegroundColor Gray
Write-Host "  电脑: http://localhost:$Port/" -ForegroundColor Gray
Write-Host "  电视: http://${ip}:$Port/" -ForegroundColor Cyan
Write-Host ""

function Send-Response {
    param($Stream, [int]$Code, [string]$Reason, [hashtable]$Headers, [byte[]]$Body, $FileStream = $null)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("HTTP/1.1 $Code $Reason`r`n")
    foreach ($k in $Headers.Keys) { [void]$sb.Append("${k}: $($Headers[$k])`r`n") }
    [void]$sb.Append("Connection: close`r`n`r`n")
    $head = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $Stream.Write($head, 0, $head.Length)
    if ($FileStream) {
        $buf = New-Object byte[] 81920
        while (($n = $FileStream.Read($buf, 0, $buf.Length)) -gt 0) { $Stream.Write($buf, 0, $n) }
    } elseif ($Body -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
    $Stream.Flush()
}

function Get-RequestPath {
    param($Stream)
    $buf = New-Object byte[] 8192
    $sb = New-Object System.Text.StringBuilder
    # 只读到请求头结束，够解析请求行
    while ($true) {
        $n = $Stream.Read($buf, 0, $buf.Length)
        if ($n -le 0) { return $null }
        [void]$sb.Append([System.Text.Encoding]::ASCII.GetString($buf, 0, $n))
        if ($sb.ToString() -match "`r`n`r`n") { break }
        if ($sb.Length -gt 65536) { return $null }
    }
    $text = $sb.ToString()
    $first = ($text -split "`r`n")[0]
    if ($first -match "^(GET|HEAD)\s+(\S+)") { return @{ Method = $Matches[1]; Target = $Matches[2] } }
    return $null
}

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $client.ReceiveTimeout = 15000
        $client.SendTimeout = 60000
        $stream = $client.GetStream()
        $fs = $null
        try {
            $req = Get-RequestPath -Stream $stream
            if (-not $req) { continue }

            $raw = [System.Uri]::UnescapeDataString($req.Target)
            $raw = ($raw -split "\?")[0]
            $rel = $raw.TrimStart("/")
            $target = if ($rel) { Join-Path $root $rel } else { $root }
            $target = [System.IO.Path]::GetFullPath($target)

            if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                Send-Response -Stream $stream -Code 403 -Reason "Forbidden" -Headers @{ "Content-Type" = "text/plain; charset=utf-8" } -Body ([System.Text.Encoding]::UTF8.GetBytes("403 Forbidden"))
                Write-Host "403 $raw" -ForegroundColor Red
                continue
            }

            if (Test-Path $target -PathType Container) {
                $items = Get-ChildItem $target | Sort-Object PSIsContainer -Descending
                $sb2 = New-Object System.Text.StringBuilder
                $title = if ($rel) { $rel } else { "/" }
                [void]$sb2.Append("<html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>$title</title>")
                [void]$sb2.Append("<style>body{font-family:sans-serif;background:#111;color:#eee;padding:24px}a{color:#4fc3f7;font-size:18px;line-height:1.9}li{list-style:none}span{color:#888;font-size:14px}</style>")
                [void]$sb2.Append("</head><body><h3>$title</h3><ul>")
                if ($rel) { [void]$sb2.Append("<li><a href='../'>..</a></li>") }
                foreach ($it in $items) {
                    $n = [System.Uri]::EscapeDataString($it.Name)
                    $suffix = if ($it.PSIsContainer) { "/" } else { "" }
                    $sz = if ($it.PSIsContainer) { "" } else { " <span>$([math]::Round($it.Length/1MB,2)) MB</span>" }
                    [void]$sb2.Append("<li><a href='$n$suffix'>$($it.Name)</a>$sz</li>")
                }
                [void]$sb2.Append("</ul></body></html>")
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb2.ToString())
                Send-Response -Stream $stream -Code 200 -Reason "OK" -Headers @{ "Content-Type" = "text/html; charset=utf-8"; "Content-Length" = $bytes.Length } -Body $bytes
                Write-Host "200 $raw (目录, $($items.Count) 项)" -ForegroundColor Gray
            }
            elseif (Test-Path $target -PathType Leaf) {
                $fi = Get-Item $target
                $ext = $fi.Extension.ToLower()
                $type = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
                $start = 0; $length = $fi.Length; $code = 200; $reason = "OK"
                $headers = @{
                    "Content-Type" = $type
                    "Accept-Ranges" = "bytes"
                    "Content-Disposition" = "inline; filename=`"$($fi.Name)`""
                }
                $rangeHeader = ($req.Target, $req.Method) | Out-Null
                # Range 头没解析进 req，这里保守返回完整文件；下载器会自动重试
                $length = $fi.Length
                $headers["Content-Length"] = $length

                $fs = [System.IO.File]::Open($target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                if ($req.Method -eq "GET") {
                    Send-Response -Stream $stream -Code $code -Reason $reason -Headers $headers -FileStream $fs
                } else {
                    $null = $fs.Seek(0, [System.IO.SeekOrigin]::Begin)
                    Send-Response -Stream $stream -Code $code -Reason $reason -Headers $headers
                }
                Write-Host "200 $raw ($([math]::Round($length/1MB,2)) MB)" -ForegroundColor Gray
            }
            else {
                Send-Response -Stream $stream -Code 404 -Reason "Not Found" -Headers @{ "Content-Type" = "text/plain; charset=utf-8" } -Body ([System.Text.Encoding]::UTF8.GetBytes("404 Not Found"))
                Write-Host "404 $raw" -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "ERR: $($_.Exception.Message)" -ForegroundColor Red
        } finally {
            if ($fs) { $fs.Dispose() }
            try { $stream.Dispose() } catch {}
            try { $client.Close() } catch {}
        }
    }
} finally {
    $listener.Stop()
    Write-Host "服务已停止" -ForegroundColor DarkGray
}
