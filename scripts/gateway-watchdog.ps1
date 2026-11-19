#requires -Version 5.1
<#
.SYNOPSIS
  modelwharf 网关守护脚本：检测网关是否在监听，不在则以隐藏窗口拉起。
.DESCRIPTION
  由计划任务周期性调用（默认每 2 分钟）。设计要点：
  1) 只认「端口 LISTENING + /health 200」双条件，避免端口被别的进程占用时误判；
  2) 用 S4U 计划任务调用，非交互会话、桌面零弹窗；
  3) 服务端 src/server.js 自带端口探测，重复拉起会安全退出，不会双开；
  4) 所有动作写 logs\gateway-watchdog.log，便于排错。
#>
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root 'logs'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$log = Join-Path $logDir 'gateway-watchdog.log'

function Write-Log([string]$msg) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch {}
}

# 运行参数从 data/gateway-runtime.json 读取（S4U 会话不继承交互 shell 的环境变量）
$runtimeFile = Join-Path $root 'data\gateway-runtime.json'
if (Test-Path -LiteralPath $runtimeFile) {
    try {
        $cfg = Get-Content -LiteralPath $runtimeFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.WH_HOST) { $env:WH_HOST = $cfg.WH_HOST }
        if ($cfg.WH_PORT) { $env:WH_PORT = $cfg.WH_PORT }
    } catch { Write-Log "WARN read gateway-runtime.json failed: $($_.Exception.Message)" }
}
if (-not $env:WH_PORT) { $env:WH_PORT = '8317' }
$port = [int]$env:WH_PORT

# 条件一：端口监听
$listening = $false
try {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($conn) { $listening = $true }
} catch {}

# 条件二：/health 200
$healthy = $false
try {
    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
    if ($resp.StatusCode -eq 200) { $healthy = $true }
} catch {}

if ($listening -and $healthy) {
    Write-Log "OK gateway alive on :$port"
    exit 0
}

Write-Log "WARN gateway down (listening=$listening healthy=$healthy), trying to start..."

# PATH 兜底：计划任务 S4U 会话的 PATH 可能不含用户级 node
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCmd) {
    Write-Log 'ERROR node not found in PATH; abort start'
    exit 1
}

$server = Join-Path $root 'src\server.js'
if (-not (Test-Path -LiteralPath $server)) {
    Write-Log "ERROR server.js not found: $server"
    exit 1
}

# 备用日志：node stdout/stderr 落盘，便于看崩溃原因
$outLog = Join-Path $logDir 'gateway-stdout.log'
$errLog = Join-Path $logDir 'gateway-stderr.log'

# 用 Win32_Process.Create 而不是 Start-Process：
# Start-Process 会把大小写重复的代理变量(http_proxy/HTTP_PROXY)塞进 .NET 字典而报错；
# Create 走命令行创建进程，不碰那套字典，且 cmd /c start "" /B 保证无窗口、不阻塞。
$nodeExe = $nodeCmd.Source
# 关键：必须把 WH_HOST/WH_PORT 显式写进启动命令行，否则子进程读不到本脚本设的 $env，
# 会 fallback 到 config.js 默认 0.0.0.0（对外网暴露）。
$listenHost = if ($env:WH_HOST) { $env:WH_HOST } else { '127.0.0.1' }
$cmdLine = 'cmd.exe /c set "WH_HOST=' + $listenHost + '"&& set "WH_PORT=' + $port + '"&& "' + $nodeExe + '" "' + $server + '" >> "' + $outLog + '" 2>> "' + $errLog + '"'
try {
    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create `
        -Arguments @{ CommandLine = $cmdLine; CurrentDirectory = $root }
    if ($result.ReturnValue -ne 0) {
        Write-Log "ERROR create process failed, ReturnValue=$($result.ReturnValue)"
        exit 1
    }
    Write-Log "STARTED node pid=$($result.ProcessId), server=$server"
} catch {
    Write-Log "ERROR start failed: $($_.Exception.Message)"
    exit 1
}

# 轮询复检最多 15 秒（冷启动可能慢于 3 秒，避免误报）
$ok = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 1
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$port/health" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) { $ok = $true; break }
    } catch {}
}
if ($ok) { Write-Log "OK gateway healthy after start (waited $($i+1)s)" }
else { Write-Log 'ERROR gateway still unhealthy after 15s; see gateway-stderr.log' }
