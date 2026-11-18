#requires -Version 5.1
# 注册开机自启（登录时自动启动网关）
$ErrorActionPreference = "Continue"

$script = Join-Path $PSScriptRoot "start-gateway.ps1"
if (-not (Test-Path $script)) {
    Write-Host "[modelwharf] 找不到 $script" -ForegroundColor Red
    exit 1
}

$tr = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $script + '"'
schtasks /Create /TN "modelwharf-gateway" /TR $tr /SC ONLOGON /RL LIMITED /F | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "[modelwharf] 已创建计划任务 modelwharf-gateway，下次登录 Windows 时自动启动"
    Write-Host "  手动立即启动: powershell -ExecutionPolicy Bypass -File `"$script`""
    Write-Host "  取消自启    : schtasks /Delete /TN modelwharf-gateway /F"
} else {
    Write-Host "[modelwharf] 创建计划任务失败（退出码 $LASTEXITCODE）" -ForegroundColor Red
}
