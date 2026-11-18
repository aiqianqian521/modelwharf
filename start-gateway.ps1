#requires -Version 5.1
# modelwharf 网关启动脚本（前台运行，关闭窗口即停止）
$ErrorActionPreference = "Stop"

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
Set-Location $PSScriptRoot

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "[modelwharf] 未找到 node，请先安装 Node.js 22.19 或更高版本" -ForegroundColor Red
    exit 1
}

if (-not $env:WH_HOST) { $env:WH_HOST = "127.0.0.1" }
if (-not $env:WH_PORT) { $env:WH_PORT = "8317" }

$port = [int]$env:WH_PORT
$busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if ($busy) {
    Write-Host "[modelwharf] 端口 $port 已被占用，可能已有实例在运行：" -ForegroundColor Yellow
    Write-Host "  http://$($env:WH_HOST):$port/admin"
    exit 0
}

Write-Host "[modelwharf] Node $(node -v) | 数据目录 $PSScriptRoot\data"
Write-Host "[modelwharf] 管理后台 http://$($env:WH_HOST):$port/admin"

node src/server.js
