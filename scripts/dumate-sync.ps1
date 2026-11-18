param(
    # modelwharf 网关地址
    [string]$Gateway = 'http://localhost:8317',
    # 网关里对应 DuMate 的账号 ID（先在后台「平台账号」里建好 openai-compat 账号）
    [int]$AccountId = 0,
    # 网关管理密码；也可用环境变量 WH_ADMIN_PASSWORD
    [string]$AdminPassword = '',
    # DuMate.exe 完整路径（客户端掉线时自动拉起用）
    [string]$AppExe = "$env:LOCALAPPDATA\Programs\DuMate\DuMate.exe",
    # 本地代理的固定路径前缀（DuMate 的千帆代理端点）
    [string]$ProxyPath = '/api/qianfanproxy/v1',
    # 同步间隔内探测上游用的模型名
    [string]$ProbeModel = 'glm-5'
)

# DuMate（千帆个人额度客户端）-> modelwharf 自动端口同步
# 背景：DuMate 的本地代理端口每次重启都会随机变化，网关里写死的 baseUrl 会失效。
# 机制：发现 dumate-main-server 进程 -> 探测代理可用性 -> 把新端口 PUT 回网关账号。
# 参数化公开版：原版硬编码账号 ID 与密码，此版全部可配，示例见 scripts/README。
# 计划任务建议以 S4U（无论是否登录）运行，避免每 10 分钟弹出控制台窗口。

$ErrorActionPreference = 'Continue'
$logFile   = Join-Path $PSScriptRoot 'dwsync.log'
$stateFile = Join-Path $PSScriptRoot 'state.json'

if (-not $AdminPassword) { $AdminPassword = $env:WH_ADMIN_PASSWORD }
if (-not $AdminPassword) { $AdminPassword = 'admin' }
if (-not $AccountId)     { throw '请用 -AccountId 指定网关里 DuMate 账号的 ID' }

function Write-Log([string]$msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -Path $logFile -Value "$ts  $msg" -Encoding UTF8
}

function Get-MainPort {
    $p = Get-CimInstance Win32_Process -Filter "Name='dumate-main-server.exe'" -ErrorAction SilentlyContinue |
         Select-Object -First 1
    if (-not $p) { return $null }
    if ($p.CommandLine -match '--port=(\d+)') { return [int]$Matches[1] }
    return $null
}

function Test-Upstream([int]$port) {
    if (-not $port) { return $false }
    $body = (@{ model = $ProbeModel; messages = @(@{ role = 'user'; content = 'ping' }); max_tokens = 8; stream = $false } | ConvertTo-Json -Depth 5)
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:$port$ProxyPath/chat/completions" `
             -Method Post -Body $body -ContentType 'application/json' `
             -Headers @{ Authorization = 'Bearer nokey' } -TimeoutSec 30 -UseBasicParsing
        return ($r.StatusCode -eq 200)
    } catch {
        Write-Log ("upstream probe error: " + $_.Exception.Message)
        return $false
    }
}

function Sync-Gateway([int]$port) {
    try {
        $login = Invoke-RestMethod -Method Post -Uri "$Gateway/admin/api/login" `
                 -ContentType 'application/json' -Body (@{ password = $AdminPassword } | ConvertTo-Json) -TimeoutSec 15
        $tok = $login.token
    } catch {
        Write-Log ("gateway login failed: " + $_.Exception.Message)
        return $false
    }
    if (-not $tok) { Write-Log 'gateway login returned empty token'; return $false }

    $base = "http://127.0.0.1:$port$ProxyPath"
    $body = @{ credentials = @{ baseUrl = $base; apiKey = 'nokey' } } | ConvertTo-Json -Depth 5
    try {
        $r = Invoke-RestMethod -Method Put -Uri "$Gateway/admin/api/accounts/$AccountId" `
             -Headers @{ Authorization = "Bearer $tok" } -ContentType 'application/json' `
             -Body $body -TimeoutSec 15
        Write-Log ("account #$AccountId baseUrl -> $base  ok=" + $r.ok)
        return [bool]$r.ok
    } catch {
        Write-Log ("gateway update failed: " + $_.Exception.Message)
        return $false
    }
}

Write-Log '=== run start ==='
$port = Get-MainPort

if (-not $port) {
    Write-Log 'dumate-main-server not running'
    if (Test-Path $AppExe) {
        Write-Log "launching $AppExe"
        try { Start-Process -FilePath $AppExe -WindowStyle Minimized | Out-Null } catch { Write-Log ("launch error: " + $_.Exception.Message) }
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 3
            $port = Get-MainPort
            if ($port) { break }
        }
    } else {
        Write-Log "app exe not found: $AppExe"
    }
    if (-not $port) { Write-Log 'client still down after wait, abort'; Write-Log '=== run end ==='; exit 1 }
    Write-Log "client up on port $port"
}

$probeOk = Test-Upstream $port
$lastPort = $null
if (Test-Path $stateFile) {
    try { $lastPort = (Get-Content $stateFile -Raw | ConvertFrom-Json).port } catch { $lastPort = $null }
}
Write-Log ("detected port=$port  upstream_ok=$probeOk  last_synced_port=$lastPort")

# 本地端口每次客户端重启都会随机化，网关里的旧值即使上游本身健康也已过期，
# 所以每轮都直接 PUT 当前端口，比读回掩码凭证再比对更省事可靠。
if (-not $probeOk) { Write-Log 'upstream probe failed, syncing anyway' }

if (Sync-Gateway $port) {
    @{ port = $port; syncedAt = (Get-Date -Format 's') } | ConvertTo-Json |
        Set-Content -Path $stateFile -Encoding UTF8
}
Start-Sleep -Seconds 1
Write-Log ("post-sync upstream_ok=" + (Test-Upstream $port))

Write-Log '=== run end ==='