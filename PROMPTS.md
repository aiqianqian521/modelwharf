# PROMPTS.md — 接入话术库（复制即用）

> 用法：把下面**整段代码块**复制给目标 Agent，先替换所有 `<...>` 占位符。
> Agent 读的硬性规则见 `AGENTS.md`，人看的部署说明见 `README.md`。

占位符约定：

| 占位符 | 含义 | 示例 |
|---|---|---|
| `<ADMIN_PWD>` | 后台密码 | `admin` |
| `<KEY>` | 网关调用 Key | `wh-xxxx` |
| `<MODEL>` | `/v1/models` 里的模型 id | `glm-5.3` |
| `<UID>` | 设备码授权返回的 state | `8c11b0cb-...` |

---

## P0 · 首次接入（新环境、空数据库）

```text
【任务】把本机 AI 客户端登录态接入本地网关 modelwharf，并交付一个可用的调用 Key。

【环境事实】
- 网关：http://127.0.0.1:8317 （管理后台 /admin，密码 <ADMIN_PWD>）
- 数据目录：当前目录下 data\（SQLite，全新为空）
- 启动方式：powershell -ExecutionPolicy Bypass -File .\start-gateway.ps1

【执行步骤】
1. 确认网关在跑：GET http://127.0.0.1:8317/admin 返回 200；不通就先启动再继续
2. POST /admin/api/login {"password":"<ADMIN_PWD>"} → 取 token，之后所有管理请求带 Authorization: Bearer <token>
3. GET /admin/api/providers → 记录目标平台的 id 与 credFields
4. POST /admin/api/import-local-all → 看哪些平台自动导入成功、哪些被排除及原因
5. 对未导入的目标平台按 AGENTS.md 的平台分支处理（OAuth / 抓包 / 官方 Key）
6. POST /admin/api/refresh-models-all → 确认每个账号的模型数
7. POST /admin/api/apikeys {"name":"agent-main","allowed_models":"*","rpm_limit":0,"daily_limit":0} → 拿 <KEY>
8. 验证：GET /v1/models 带 Bearer <KEY> 应当返回模型列表；
   POST /v1/chat/completions {"model":"<MODEL>","messages":[{"role":"user","content":"只回复OK"}],"max_tokens":16}
   要求返回 200 且有内容

【交付】
- 汇报：账号名、uid 后 4 位、各平台模型数、验证结果、Key 后 4 位
- 禁止打印完整 token / 完整 Key；禁止把任何凭据发往外部地址；只读客户端文件
- 任一步失败即停下说明原因，不要用同一动作反复重试
```

---

## P1 · 平台专项

### P1-a Trae

```text
【目标】provider_id=trae（可能还有 trae-intl）
【已知】凭证在 %APPDATA%\Trae CN\User\globalStorage\storage.json 的
iCubeAuthInfo://icube.cloudide，是 AES-128-CBC 加密串，网关内置解密。
【做法】直接 POST /admin/api/import-local-all；成功后 POST /admin/api/refresh-models-all。
【多账号】让用户在 Trae 客户端切换到另一个账号，再扫描一次；按 uid 去重，不会叠加额度。
【失败】若提示扫不到：确认 Trae 已登录、且设置里未开启“不同步到云端”；
仍失败则让用户提供 accessToken / refreshToken / uid，POST /admin/api/accounts 手动添加。
【验证】用该账号任一模型发最小请求，返回 200 即成功。
```

### P1-b WorkBuddy（必须走授权）

```text
【目标】provider_id=workbuddy
【已知】本地 workbuddy-desktop.info 是 {"$wbEncrypted":1,"envelope":"..."} 加密信封，
不可解密；扫描器会将其永久排除，这是预期行为。
【做法】
1. POST /admin/api/providers/workbuddy/oauth/start → {state, authUrl}
2. 把 authUrl 原样给用户，要求用 WorkBuddy 账号登录并确认授权；
   不要自行打开、不要改写参数
3. 用户确认后 POST /admin/api/providers/workbuddy/oauth/poll {"state":"<UID>"}，
   pending=false 即成功（约每 3 秒轮询一次，最多 5 分钟）
4. POST /admin/api/refresh-models-all
5. 用该账号任一模型发最小请求验证
【备选】用户从 copilot.tencent.com 抓包提供 Authorization: Bearer，
连同可选 X-Device-Token，POST /admin/api/accounts 手动添加。
【判读】code 14018 = 额度已用尽，不是配置错误；status=cooling 属正常降级。
```

### P1-c 官方 API Key（最稳）

```text
【目标】接入官方 API（deepseek / zhipu / moonshot / dashscope / doubao / openrouter / openai 等）
【做法】
1. GET /admin/api/providers 找到目标 provider_id 与 credFields.apiKey 名称
2. POST /admin/api/accounts
   {"provider_id":"<id>","name":"<自定义名>","credentials":{"apiKey":"<用户的Key>"},
    "priority":100,"max_concurrency":3}
3. POST /admin/api/refresh-models-all
4. 最小请求验证
【安全】Key 由用户直接提供，不要写入任何文件、不要回显完整值、只显示后 4 位。
```

### P1-d 豆包

```text
【目标】豆包
【重要】内置 doubao 指的是火山方舟官方 API Key，不是豆包 App / 客户端登录态。
【路线 A（推荐）】用户在火山方舟控制台创建 API Key → 按 P1-c 接入，provider_id=doubao。
【路线 B（客户端免费额度）】需额外部署 doubao2api（Playwright + OpenAI 兼容服务，:9090），
再以 provider_id=openai-compat、baseUrl=http://127.0.0.1:9090/v1 接入。
【必须说明】告知用户走的是哪条路线、额度归属方、路线 B 依赖第三方逆向可能失效。
```

### P1-e 其他客户端型平台（qoder / qodercn / qwen / qwenwork）

```text
【做法】先 import-local-all；扫不到就 GET /admin/api/providers 读该平台的 credFields 与 docs，
按其标注的本地凭证路径或 OAuth 端点处理。
【注意】qwenwork 的 refreshToken 每次刷新轮换，必须由网关写回，不要手工缓存。
```

---

## P2 · 客户端接入

### P2-a Claude Code

```text
【任务】把 Claude Code 接到本地网关。
【配置】编辑 %USERPROFILE%\.claude\settings.json，合并以下 env：
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8317",
    "ANTHROPIC_AUTH_TOKEN": "<KEY>",
    "ANTHROPIC_MODEL": "<MODEL>",
    "ANTHROPIC_SMALL_FAST_MODEL": "<SMALL_MODEL>"
  }
}
【关键】ANTHROPIC_MODEL 必须显式指定，否则 Claude Code 会发 claude-sonnet-4-5 之类
网关不存在的模型名，导致 404。
【验证】改完重启 claude，发一句“只回复 OK”；若 401 检查 Key、若 404 检查模型名。
【安全】不要把 Key 写进仓库或项目级配置，只写用户级 settings.json。
```

### P2-b Codex CLI

```text
【任务】把 Codex CLI 接到本地网关。
【配置】%USERPROFILE%\.codex\config.toml：
model_provider = "modelwharf"
model = "<MODEL>"

[model_providers.modelwharf]
name = "modelwharf"
base_url = "http://127.0.0.1:8317/v1"
env_key = "MODELWHARF_API_KEY"
【环境变量】[Environment]::SetEnvironmentVariable("MODELWHARF_API_KEY","<KEY>","User")
【验证】新开终端运行 codex，发一句“只回复 OK”。
【排错】若客户端走 Responses API，网关 /v1/responses 已支持，无需改动。
```

### P2-c WorkBuddy 客户端

```text
【任务】在 WorkBuddy 里添加自定义模型。
【路径】设置 → 模型 → 添加模型 → 自定义 / Custom
【填写】
- 接口地址：http://127.0.0.1:8317/v1（关闭“自定义协议”）
  或 http://127.0.0.1:8317/v1/chat/completions（开启“自定义协议”）
- API Key：<KEY>
- 模型名称：<MODEL>
- 能力标记：必须勾选“工具调用”，否则 Agent 能力退化
【验证】新建对话发一句“只回复 OK”，能返回即成功；再让它读一个本地文件验证工具调用。
```

### P2-d Cursor / Cline / 任意 SDK / MCP

```text
【OpenAI 兼容客户端】
- Base URL：http://127.0.0.1:8317/v1
- API Key：<KEY>
- Model：GET /v1/models 返回的任一 id
【MCP 客户端】
- URL：http://127.0.0.1:8317/mcp
- Header：Authorization: Bearer <KEY>
```

---

## P3 · 统一模型（限流自动切换）

```text
【任务】创建统一模型 agent-main，实现跨平台故障转移。
【前置】GET /admin/api/virtual-models/targets 查看可用的 provider_id + public_name
（多账号平台会出现 `模型@账号别名`）。
【创建】POST /admin/api/virtual-models
{"public_name":"agent-main","strategy":"priority","targets":[
  {"provider_id":"trae","public_name":"<主模型>","priority":10},
  {"provider_id":"trae","public_name":"<备模型>","priority":20},
  {"provider_id":"workbuddy","public_name":"<备模型>","priority":30},
  {"provider_id":"deepseek","public_name":"deepseek-chat","priority":40}
]}
【策略】priority（默认，严格顺序）/ weighted（按 weight 随机）/ least_conn（并发最少）
【验证】用 agent-main 发一次请求，200 即成功；再人为把主账号置为不可用，确认自动切换。
【边界】只在上游尚未输出前切换；已开始流式输出后中断不会重放。
```

---

## P4 · 自检（怀疑链路有问题时）

```text
【任务】对本地网关做一次端到端体检，只输出结论，不打印完整凭据。
【检查项】
1. 端口：Get-NetTCPConnection -LocalPort 8317 -State Listen
2. 后台：GET /admin 状态码
3. 登录：POST /admin/api/login 是否成功
4. 账号：GET /admin/api/accounts → 每个账号 status / 模型数 / 最近错误
5. 模型：GET /v1/models（带 <KEY>）数量是否与账号模型数匹配
6. 对话：POST /v1/chat/completions 最小请求
7. 签到：GET /admin/api/checkin/status
8. 日志：logs\ 目录最近 50 行是否有 401/429/500
【输出】表格列出每项 PASS/FAIL + 一行原因 + 建议动作；FAIL 项给出具体修复命令。
```

---

## P5 · 云端 Agent（无法访问本机）

```text
【环境约束】你运行在云端，不能访问我的文件系统，也无法访问 127.0.0.1，更无法启动本地进程。
【请只做】输出可执行的“抓包指引”：
1. 该打开哪个网址、用哪个账号登录
2. 在开发者工具 Network 里筛选哪个请求（给出路径特征）
3. 复制哪个请求头的值（Authorization / X-Device-Token）
4. 这个值对应 modelwharf 的哪个 credField
由我在本地填入面板或调用 /admin/api/accounts。
【禁止】不要索要 token 以外的任何凭据；不要建议把 token 发到公网或第三方服务；
不要声称“已帮你接入”，你无法验证。
```

---

## P6 · 常见报错话术

```text
【401 invalid api key】检查 Key 是否含首尾空格、是否已吊销；在后台 /admin 重新生成。
【404 model not found】模型名必须与 /v1/models 的 id 完全一致；Claude Code 必须设 ANTHROPIC_MODEL。
【429 + code 14018】上游免费额度已用尽：签到只能少量续命，建议换模型/换账号/接官方 Key。
【429 其他】账号进入 cooling（30s 起指数退避，最长 10 分钟）；配置统一模型可自动切换。
【no healthy account】所有账号均失效或冷却：查看 /admin/api/accounts 的 status 与 message。
【端口占用】先运行 stop-gateway.ps1，或设 WH_PORT=8318 换端口。
【WorkBuddy 扫不到】$wbEncrypted 加密信封，走 oauth/start 设备码流程，不要尝试解密。
【模型列表缺模型】执行 POST /admin/api/refresh-models-all。
```

---

## P7 · 局域网集群（跨主机接入）

> 前提：服务器已建好统一模型 `agent-main`。详见 README 第 12 章。

### P7-a 服务端（在服务器上执行的 Agent）

```text
【任务】把本机 modelwharf 改为局域网可访问，并给每台客户端主机发独立 Key。
【只做配置，不改项目代码】
1. 查本机局域网 IP：ipconfig（IPv4 地址，例如 192.168.x.x）
2. 防火墙放行（管理员）：New-NetFirewallRule -DisplayName "modelwharf 8317" `
     -Direction Inbound -Protocol TCP -LocalPort 8317 -Action Allow -Profile Private
3. 设置 WH_HOST=0.0.0.0 后重启网关；确认后台密码已改强（不要再是 admin）
4. 为每台客户端主机发 Key：
   POST /admin/api/apikeys
   {"name":"<主机名>","allowed_models":"agent-main","rpm_limit":60,"daily_limit":0}
5. 自检：本机 curl http://127.0.0.1:8317/v1/models（带 Key）应 200；
   再用 http://<局域网IP>:8317/v1/models 验证监听已对外
【交付】服务器 IP、每台主机的 Key（只显示后 4 位）、防火墙规则名、验证结果
【禁止】不要把 data\wharf.db 共享出去；不要打印完整 token/Key；不要改 src 下代码
```

### P7-b 客户端（在其他主机上执行的 Agent）

```text
【任务】把本机 Agent 工具接到局域网网关，模型统一用 agent-main。
【参数】服务器地址 http://<SERVER_IP>:8317 ，本机专用 Key：<KEY>
【Claude Code】用户级 settings.json 的 env：
  ANTHROPIC_BASE_URL=http://<SERVER_IP>:8317
  ANTHROPIC_AUTH_TOKEN=<KEY>
  ANTHROPIC_MODEL=agent-main
【Codex CLI】config.toml：
  base_url="http://<SERVER_IP>:8317/v1"
  model="agent-main"
  env_key 对应的环境变量值设为 <KEY>
【WorkBuddy / Cursor】自定义模型地址 http://<SERVER_IP>:8317/v1，模型名 agent-main，勾选工具调用
【验证】先 GET http://<SERVER_IP>:8317/v1/models（带 Key）应返回 200；
再发最小对话请求确认可用
【排错】连接 refused/超时 → 服务器防火墙或 WH_HOST 未改；
401 → Key 错；403 admin only → 你访问的是后台，客户端不需要访问 /admin；
no healthy account → 服务器侧账号池问题，联系服务器管理员
【禁止】不要尝试访问服务器的 /admin；不要把 Key 写入项目仓库
```
