#requires -Version 5.1
# 停止 modelwharf 网关
$ErrorActionPreference = "Continue"

if (-not $env:WH_PORT) { $env:WH_PORT = "8317" }
$port = [int]$env:WH_PORT
$conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue

if (-not $conn) {
    Write-Host "[modelwharf] 端口 $port 上没有监听进程，未在运行"
    exit 0
}

foreach ($c in $conn) {
    $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
    if ($p) {
        Write-Host "[modelwharf] 停止 PID $($p.Id) ($($p.ProcessName))"
        Stop-Process -Id $p.Id -Force
    }
}
Write-Host "[modelwharf] 已停止"
