#requires -Version 5.1
<#
.SYNOPSIS
  注册 modelwharf 网关为「后台默认自启 + 崩溃自愈」计划任务。
.DESCRIPTION
  与旧版的差别：
  - 旧版：ONLOGON 单次触发，只调 start-gateway.ps1，进程死了不会自己起来；
  - 新版：S4U 非交互（桌面零弹窗），登录时触发 + 每 N 分钟巡检，
    由 scripts\gateway-watchdog.ps1 检测不健康时自动拉起，不依赖任何 Agent 接管。

  幂等：重复执行覆盖同名任务，不会叠加。
  取消自启：schtasks /Delete /TN modelwharf-gateway /F
#>
param(
    [string]$ListenHost = '127.0.0.1',   # 网关监听地址；局域网可传 0.0.0.0
    [int]$Port = 8317
)
$ErrorActionPreference = 'Stop'

$taskName = 'modelwharf-gateway'
$watchdog = Join-Path $PSScriptRoot 'scripts\gateway-watchdog.ps1'
if (-not (Test-Path -LiteralPath $watchdog)) {
    Write-Host "[modelwharf] 找不到 $watchdog" -ForegroundColor Red
    exit 1
}

# 持久化运行参数，供 S4U 会话里的守护脚本读取（不依赖交互 shell 环境变量）
$dataDir = Join-Path $PSScriptRoot 'data'
if (-not (Test-Path -LiteralPath $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
$runtimeFile = Join-Path $dataDir 'gateway-runtime.json'
@{ WH_HOST = $ListenHost; WH_PORT = $Port } | ConvertTo-Json | Set-Content -LiteralPath $runtimeFile -Encoding UTF8 -Force

# 巡检间隔（分钟），可用环境变量覆盖
$interval = 2
if ($env:WH_WATCH_INTERVAL -match '^\d+$' -and [int]$env:WH_WATCH_INTERVAL -gt 0) {
    $interval = [int]$env:WH_WATCH_INTERVAL
}

# 静默、非交互、登录前后都能跑（与 DuMate 同步任务同款 S4U 模式）
$arg    = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $watchdog + '"'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg

# 触发器 1：每 N 分钟巡检（不设 RepetitionDuration = 无限重复；StartWhenAvailable 保证错过的点补跑）
$tLoop = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
         -RepetitionInterval (New-TimeSpan -Minutes $interval)
# 触发器 2：登录时立即巡检一次（比等第一个巡检周期更快恢复）
$tLogon = New-ScheduledTaskTrigger -AtLogOn

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
             -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($tLoop, $tLogon) `
        -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
} catch {
    Write-Host "[modelwharf] 注册任务失败: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$t = Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
$i = Get-ScheduledTaskInfo -TaskName $taskName
$logPath = Join-Path $PSScriptRoot 'logs\gateway-watchdog.log'
$state   = $t.State
$logon   = $t.Principal.LogonType
$next    = $i.NextRunTime
Write-Host "[modelwharf] 已注册后台自启任务 $taskName"
Write-Host "  状态      : $state"
Write-Host "  登录类型  : $logon (S4U 非交互, 桌面零弹窗)"
Write-Host "  巡检间隔  : 每 $interval 分钟 + 登录时立即一次"
Write-Host "  下次运行  : $next"
Write-Host "  守护脚本  : $watchdog"
Write-Host "  守护日志  : $logPath"
Write-Host "  立即启动  : powershell -ExecutionPolicy Bypass -File $watchdog"
Write-Host "  取消自启  : schtasks /Delete /TN $taskName /F"

# 注册完立刻巡检一次，不必等下一个周期
& $watchdog
