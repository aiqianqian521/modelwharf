param(
    # 这三个参数会透传给 dumate-sync.ps1；其余参数用默认值即可
    [int]$AccountId = 0,
    [string]$Gateway = 'http://localhost:8317',
    [string]$AdminPassword = '',
    # 默认整点运行（每小时 :00 一次）；需要高频时可传 -RunAtHour:$false 并用 -IntervalMinutes 指定间隔
    [bool]$RunAtHour = $true,
    [int]$IntervalMinutes = 60
)

# 注册「DuMate -> modelwharf 端口同步」计划任务（静默后台运行）
#
# 为什么用 S4U（无论是否登录都运行）而不是普通交互任务：
#   交互任务每隔一段时间就会在桌面弹出一次控制台窗口，非常烦人；
#   S4U 任务运行在非交互会话，桌面上完全无窗口，且登录前也能跑。
#   代价：S4U 会话里拉起的 DuMate 后台运行，桌面看不到其窗口（日常 DuMate 常驻则无感）。
#
# 运行频率：默认整点运行（每小时 :00 一次），起点对齐到下一个整点。
#   需要更高频时：加 -RunAtHour:$false -IntervalMinutes 10
#
# 用法示例：
#   powershell -ExecutionPolicy Bypass -File register-dumate-sync.ps1 -AccountId 5
#   （密码默认读环境变量 WH_ADMIN_PASSWORD，或用 -AdminPassword 传入）

$ErrorActionPreference = 'Stop'
$taskName = 'DuMate-Modelwharf-Sync'
$script   = Join-Path $PSScriptRoot 'dumate-sync.ps1'

if (-not $AccountId) { throw '请用 -AccountId 指定网关里 DuMate 账号的 ID（后台「平台账号」页可见）' }

$arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $script + '"'
$arg += ' -AccountId ' + $AccountId + ' -Gateway ' + $Gateway
if ($AdminPassword) {
    # 计划任务命令行对用户可见，密码建议用环境变量而非明文写进任务参数
    $arg += ' -AdminPassword "' + $AdminPassword + '"'
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
if ($RunAtHour) {
    # 起点对齐到下一个整点，间隔 1 小时 => 每次都在 :00 运行
    $next = (Get-Date).AddHours(1)
    $start = [datetime]::new($next.Year, $next.Month, $next.Day, $next.Hour, 0, 0)
    $interval = New-TimeSpan -Hours 1
} else {
    $start = (Get-Date).AddMinutes(1)
    $interval = New-TimeSpan -Minutes $IntervalMinutes
}
$trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval $interval
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
             -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null

$t = Get-ScheduledTask -TaskName $TaskName
$i = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Output ("TaskName   : " + $t.TaskName)
Write-Output ("State      : " + $t.State)
Write-Output ("LogonType  : " + $t.Principal.LogonType + "  （非交互会话，桌面不弹窗）")
Write-Output ("Action     : " + $t.Actions[0].Execute + ' ' + $t.Actions[0].Arguments)
Write-Output ("NextRunTime: " + $i.NextRunTime)