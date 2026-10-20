<#
.SYNOPSIS
    在电脑上起一个局域网 HTTP 文件服务，电视盒子用浏览器/下载器直接拉文件。

.DESCRIPTION
    适合临时传 APK、字幕、图片这类小文件。
    比 U 盘快，不用装任何 App —— 电视自带的浏览器或下载器打开 URL 即可。
    服务持续运行，Ctrl+C 停止。

.EXAMPLE
    .\lan-share.ps1 -Path E:\aiprojects\hongguoTV\outputs

.EXAMPLE
    .\lan-share.ps1 -Path . -Port 8090
#>
[CmdletBinding()]
param(
    [string]$Path = ".",
    [int]$Port = 8090,
    [string]$BindAddress = "0.0.0.0"
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path $Path).Path
if (-not (Test-Path $root -PathType Container)) { throw "不是目录: $root" }

$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and $_.InterfaceAlias -notmatch "Virtual|WSL|Tailscale|Kerio" } |
    Select-Object -First 1).IPAddress
if (-not $ip) { $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object -First 1).IPAddress }

$prefix = "http://$($BindAddress):$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host ""
Write-Host "局域网文件服务已启动" -ForegroundColor Green
Write-Host "  目录: $root" -ForegroundColor Gray
Write-Host "  电脑访问:  http://localhost:$Port/" -ForegroundColor Cyan
Write-Host "  电视访问:  http://${ip}:$Port/" -ForegroundColor Cyan
Write-Host "  (电视浏览器/下载器输入上面地址；Ctrl+C 停止)" -ForegroundColor DarkGray
Write-Host ""

$mime = @{
    ".apk" = "application/vnd.android.package-archive"
    ".mp4" = "video/mp4"
    ".mkv" = "video/x-matroska"
    ".jpg" = "image/jpeg"; ".jpeg" = "image/jpeg"; ".png" = "image/png"
    ".srt" = "text/plain; charset=utf-8"; ".ass" = "text/plain; charset=utf-8"
    ".txt" = "text/plain; charset=utf-8"; ".html" = "text/html; charset=utf-8"
    ".zip" = "application/zip"; ".json" = "application/json"
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        try {
            $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart("/")
            $target = if ($rel) { Join-Path $root $rel } else { $root }
            $target = [System.IO.Path]::GetFullPath($target)

            if (-not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                $res.StatusCode = 403
                $msg = [System.Text.Encoding]::UTF8.GetBytes("403 Forbidden")
                $res.OutputStream.Write($msg, 0, $msg.Length)
                Write-Host "403 $($req.Url.AbsolutePath)" -ForegroundColor Red
                continue
            }

            if (Test-Path $target -PathType Container) {
                $items = Get-ChildItem $target | Sort-Object PSIsContainer -Descending
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.Append("<html><head><meta charset='utf-8'><title>$root</title></head><body>")
                [void]$sb.Append("<h3>$(if ($rel) { $rel } else { '/' })</h3><ul>")
                if ($rel) { [void]$sb.Append("<li><a href='../'>..</a></li>") }
                foreach ($it in $items) {
                    $n = [System.Uri]::EscapeDataString($it.Name)
                    $suffix = if ($it.PSIsContainer) { "/" } else { "" }
                    $sz = if ($it.PSIsContainer) { "" } else { " <span style='color:#888'>$([math]::Round($it.Length/1MB,2)) MB</span>" }
                    [void]$sb.Append("<li><a href='$n$suffix'>$($it.Name)</a>$sz</li>")
                }
                [void]$sb.Append("</ul><p style='color:#888'>由 lan-share.ps1 提供</p></body></html>")
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
                $res.ContentType = "text/html; charset=utf-8"
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
                Write-Host "200 $($req.Url.AbsolutePath) (目录)" -ForegroundColor Gray
            }
            elseif (Test-Path $target -PathType Leaf) {
                $fi = Get-Item $target
                $ext = $fi.Extension.ToLower()
                $res.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
                $res.ContentLength64 = $fi.Length
                $res.AddHeader("Content-Disposition", "inline; filename=`"$($fi.Name)`"")
                $fs = [System.IO.File]::OpenRead($target)
                try { $fs.CopyTo($res.OutputStream) } finally { $fs.Dispose() }
                Write-Host "200 $($req.Url.AbsolutePath) ($([math]::Round($fi.Length/1MB,2)) MB)" -ForegroundColor Gray
            }
            else {
                $res.StatusCode = 404
                $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
                $res.OutputStream.Write($msg, 0, $msg.Length)
                Write-Host "404 $($req.Url.AbsolutePath)" -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "ERR $($req.Url.AbsolutePath): $($_.Exception.Message)" -ForegroundColor Red
            try { $res.StatusCode = 500 } catch {}
        } finally {
            try { $res.Close() } catch {}
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Write-Host "服务已停止" -ForegroundColor DarkGray
}
