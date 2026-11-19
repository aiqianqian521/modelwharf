# modelwharf 本地 AI 网关（便携部署包）

统一把 Trae / WorkBuddy / Qoder / 千问办公 等客户端的登录态，以及官方 API Key，
收敛成一个 **OpenAI 兼容 + Anthropic 兼容 + MCP** 的本地接口，供任何 Agent 工具调用。
当前版本共 **33 个平台通道**（含 24 家官方 API，以及客户端型平台）。

```
Claude Code / Codex CLI / WorkBuddy / Cursor / Cline / 自研脚本
                     │  http://127.0.0.1:8317
                     ▼
              modelwharf 网关
       ┌─────────────┼──────────────┐
    账号池(登录态)   官方 API Key    统一模型/故障转移
       │                              │
   Trae / WorkBuddy / Qoder ...    OpenAI / Anthropic / MCP
```

- 版本：0.13.1
- 默认端口：8317
- 数据目录：`data/`（SQLite，**含明文凭证，勿外发**）

配套文档：

| 文件 | 用途 |
|---|---|
| `README.md` | 部署、账号接入、客户端配置、排错（本文） |
| `AGENTS.md` | 给 AI Agent 的操作契约与硬性约束 |
| `PROMPTS.md` | 接入话术库，复制给其他 Agent 直接执行 |

---

## 1. 前置条件

| 项 | 要求 |
|---|---|
| 系统 | Windows 10/11（本包在 Windows 上验证） |
| Node.js | **≥ 22.19**（本机已验证 26.13） |
| 依赖 | 已随包携带 `node_modules`，无需联网安装 |

检查 Node：

```powershell
node -v
```

若命令不存在，先装 Node 22 LTS 或更高版本。

---

## 2. 启动 / 停止 / 开机自启

### 手动启动

双击或在 PowerShell 执行：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\mysite\modelwharf\start-gateway.ps1"
```

脚本会：检查端口占用 → 设置 `WH_HOST=127.0.0.1`（仅本机可访问）→ 前台运行并打印日志。

### 后台启动（不占窗口）

```powershell
Start-Process powershell -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File C:\mysite\modelwharf\start-gateway.ps1"
```

包内也保留了上游的 `start-hidden.bat` / `stop.bat`。

### 开机自启（推荐）

```powershell
powershell -ExecutionPolicy Bypass -File "C:\mysite\modelwharf\install-autostart.ps1"
```

会创建一个名为 `modelwharf-gateway` 的登录时计划任务。卸载：

```powershell
schtasks /Delete /TN "modelwharf-gateway" /F
```

### 常用环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `WH_PORT` | `8317` | 监听端口 |
| `WH_HOST` | `0.0.0.0`（脚本内已改为 `127.0.0.1`） | 监听地址，**建议保持 127.0.0.1**；确需局域网集群接入见第 12 章 |
| `WH_ADMIN_PASSWORD` | `admin` | 后台登录密码，**首次启动后务必修改** |
| `WH_DATA_DIR` | `<包目录>\data` | 数据库与配置目录 |
| `WH_LOG_DIR` | `<包目录>\logs` | 日志目录 |
| `WH_REQUEST_TIMEOUT_MS` | `300000` | 上游请求超时（5 分钟） |
| `WH_API_KEYS` | 空 | 预置调用密钥（逗号分隔），留空则用后台生成的 Key |

---

## 3. 第一次登录后台

1. 浏览器打开 **http://127.0.0.1:8317/admin**
2. 默认密码：`admin`
3. 登录后到「设置」修改密码，或下次启动前设置 `WH_ADMIN_PASSWORD`

> 后台是本地管理面，不要暴露到公网。若确实需要远程访问，请套 HTTPS 反向代理并改强密码。

---

## 4. 接入账号（核心步骤）

四种途径，按平台特性选择。

### 4.1 一键扫描本机（最快）

后台 →「平台账号」→「扫描本机」，或调用：

```powershell
$t = (Invoke-RestMethod http://127.0.0.1:8317/admin/api/login -Method Post -ContentType application/json -Body '{"password":"admin"}').token
Invoke-RestMethod http://127.0.0.1:8317/admin/api/import-local-all -Method Post -Headers @{Authorization="Bearer $t"}
Invoke-RestMethod http://127.0.0.1:8317/admin/api/refresh-models-all -Method Post -Headers @{Authorization="Bearer $t"}
```

能解密的客户端会被直接导入；同一账号（同 uid）重复扫描会自动去重。

> WorkBuddy 会被扫描器**永久加入排除名单**并返回明确原因（`$wbEncrypted` 加密信封），
> 这是正常行为，不是故障——请按 4.3 走设备码授权或抓包手动添加。

### 4.2 Trae（字节）

- 凭证位置：`%APPDATA%\Trae CN\User\globalStorage\storage.json` 中的 `iCubeAuthInfo://icube.cloudide`
- 内容为 AES-128-CBC 加密串，**网关内置解密**，所以「扫描本机」可直接拿到 `token + refreshToken + uid`
- 多账号：在 Trae 客户端切换到另一个账号 → 再扫描一次（按 uid 去重）
- refreshToken 用于自动续期；只填 token 的话约 28 天后需重新导入
- 「设置 → 通用」里的选项若开启“不同步到云端”，token 可能不在本地

### 4.3 WorkBuddy（腾讯）

**注意：本地凭证是加密信封，无法解密。**

`%LOCALAPPDATA%\CodeBuddyExtension\Data\Public\auth\workbuddy-desktop.info` 内容形如：

```json
{"$wbEncrypted":1,"envelope":"..."}
```

因此只有两条路：

**路线 A：设备码授权（推荐，能拿到 refreshToken）**

1. 后台 →「平台账号」→ 添加 → WorkBuddy → 「网页授权」，或调用：
   ```powershell
   POST /admin/api/providers/workbuddy/oauth/start
   → 返回 {"state":"<uuid>","authUrl":"https://copilot.tencent.com/login?platform=CLI&state=<uuid>"}
   ```
2. 用浏览器打开返回的 `authUrl`，用 **WorkBuddy 账号**登录并确认授权
3. 轮询检查状态（每 3 秒一次，最多 5 分钟）：
   ```powershell
   POST /admin/api/providers/workbuddy/oauth/poll {"state":"<state值>"}
   → 返回 {"pending":false, "account_id":<数字>, "name":"...", "identity":{...}}
   ```
   `pending=false` 且 `account_id` 存在即成功
4. 确认账号已导入：`GET /admin/api/accounts` 找 `provider_id=workbuddy` 的记录
5. 同步模型：`POST /admin/api/refresh-models-all`
6. 验证：用该账号任一模型发最小请求，返回 200 即成功

**路线 B：抓包（拿不到 refreshToken，约 1 个月重抓一次）**

1. 浏览器打开 `https://copilot.tencent.com` 并登录
2. F12 → Network → 任一接口请求 → 复制请求头：
   - `Authorization: Bearer xxx`（必填）
   - `X-Device-Token`（可选，某些风控场景需要）
3. 后台手动添加账号，粘贴 token；有 `X-Device-Token` 一并填
4. 同步模型并验证

CredFields：`token`（必填）、`refreshToken`、`userId`、`deviceToken`、`region`（默认 `cn`）。

**账号状态判读**

| 状态 | 含义 | 处理 |
|---|---|---|
| `active` | 正常可用 | 无需处理 |
| `cooling` | 临时冷却（429/5xx 触发） | 30 秒到 10 分钟后自动恢复 |
| `banned` | `code 14018` 额度已用尽 | 签到可少量续命，建议接官方 API 兜底 |
| `invalid` | token 失效 | 重新授权或抓包 |

**验证清单**

- [ ] `GET /admin/api/accounts` 有 `workbuddy` 账号
- [ ] 该账号 `model_count` > 0（或 `refresh-models-all` 后 > 0）
- [ ] `POST /v1/chat/completions` 用 workbuddy 模型返回 200
- [ ] 若返回 `14018`，说明额度耗尽，不是接入失败

### 4.4 官方 API Key（最稳，适合长期跑 Agent）

后台 →「平台账号」→ 添加 → 选择厂商 → 填 API Key。支持 24 家，常见：

| 平台 | provider_id | 备注 |
|---|---|---|
| DeepSeek | `deepseek` | 便宜、稳定，适合做 Codex 后端 |
| 智谱 GLM | `zhipu` | glm-4.6 / glm-4.5-air |
| 月之暗面 Kimi | `moonshot` | kimi-k2 系列 |
| 阿里百炼 / 通义 | `dashscope` | qwen3-coder-plus 等 |
| 火山方舟（豆包） | `doubao` | 需在方舟控制台创建 API Key |
| OpenRouter | `openrouter` | 一家覆盖多家 |
| 任意 OpenAI 兼容服务 | `openai-compat` | 填 `baseUrl` + `apiKey` |

> **豆包注意**：包内 `doubao` 是「火山方舟官方 API」，不是豆包 App 登录态。
> 想用客户端免费额度，需要额外部署 `doubao2api`（Playwright + OpenAI 兼容服务，默认 :9090），
> 再以 `openai-compat` 方式接入 `http://127.0.0.1:9090/v1`。该方案依赖第三方逆向，签名变更会失效。

### 4.5 其他客户端型平台

`qoder` / `qodercn`（Qoder）、`qwen`（通义网页）、`qwenwork`（千问办公）：

- 先试「扫描本机」
- 扫不到就到「平台账号 → 添加」查看该平台的 credFields 与内嵌说明
- `qwenwork` 的 refreshToken **每次刷新都会轮换**，必须由网关写回数据库，不要手工缓存旧值

### 4.6 DuMate（千帆个人额度，端口自动同步）

DuMate 是百度千帆个人额度客户端，在本机起一个 OpenAI 兼容代理（`http://127.0.0.1:<随机端口>/api/qianfanproxy/v1`）。它有个特性：**本地代理端口每次重启都随机变化**，网关里写死的 baseUrl 很快失效。

接入分两步：

**第一步：网关建账号**（一次性）

后台 →「平台账号」→ 添加 → `openai-compat` → 填当前端口：

```
baseUrl: http://127.0.0.1:<当前端口>/api/qianfanproxy/v1
apiKey: nokey（占位，代理不校验）
```

**第二步：注册端口自动同步**（推荐，否则每次重启 DuMate 都要手改 baseUrl）

```powershell
# AccountId 换成第一步建好的账号 ID（后台「平台账号」页可见）
powershell -ExecutionPolicy Bypass -File scripts\register-dumate-sync.ps1 -AccountId 3
```

脚本做了什么：

- 每 10 分钟探测 `dumate-main-server.exe` 的当前端口，自动 PUT 回网关账号的 baseUrl
- DuMate 没在跑时自动拉起客户端，等它就绪再同步
- 以 **S4U 计划任务**（无论是否登录）运行 —— 普通交互任务每 10 分钟会在桌面弹一次控制台窗口，S4U 在非交互会话运行，**桌面零弹窗**；代价是 S4U 会话里拉起的 DuMate 后台运行（DuMate 常驻时无感知）
- 日志与状态：`~/.dumate-sync/dwsync.log`、`state.json`（脚本目录下）

> **注意**：同步脚本登录网关用的密码默认 `admin`，生产环境请先用 `WH_ADMIN_PASSWORD` 环境变量或 `-AdminPassword` 改强密码，与 3 节后台密码保持一致。
> S4U 会话里无法读取登录用户的网络映射盘，脚本只访问本机回环地址，不受影响。

脚本参数与手工排错见 `scripts/dumate-sync.ps1` 头部注释；完整实现（探测、拉起、探活、写回）也是那一个文件。

---

## 5. 同步模型 & 生成调用密钥

```powershell
# 同步所有账号能用的模型（新加账号后必须做）
POST /admin/api/refresh-models-all

# 生成给客户端用的 Key（可限制模型/频率/日额度）
POST /admin/api/apikeys   body {"name":"claude-code","allowed_models":["glm-5.3"],"rpm_limit":60}
```

查看可用模型（带 Key 调）：

```powershell
curl http://127.0.0.1:8317/v1/models -H "Authorization: Bearer wh-xxxxxxxx"
```

> 模型名必须与 `/v1/models` 返回的 `id` **完全一致**，否则上游会 404。

---

## 6. 客户端接入

### 6.1 Claude Code

编辑 `%USERPROFILE%\.claude\settings.json`：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8317",
    "ANTHROPIC_AUTH_TOKEN": "wh-你的网关Key",
    "ANTHROPIC_MODEL": "glm-5.3",
    "ANTHROPIC_SMALL_FAST_MODEL": "glm-5.3-flash"
  }
}
```

- `ANTHROPIC_MODEL` **必须指定**：Claude Code 会默认发 `claude-sonnet-4-5` 之类的模型名，网关没有这些名字会 404
- 改完重启 `claude`

### 6.2 Codex CLI

编辑 `%USERPROFILE%\.codex\config.toml`：

```toml
model_provider = "modelwharf"
model = "glm-5.3"

[model_providers.modelwharf]
name = "modelwharf"
base_url = "http://127.0.0.1:8317/v1"
env_key = "MODELWHARF_API_KEY"
```

再设置环境变量（用户级）：

```powershell
[Environment]::SetEnvironmentVariable("MODELWHARF_API_KEY","wh-你的网关Key","User")
```

### 6.3 WorkBuddy 客户端

设置 → 模型 → 添加模型 → **自定义 / Custom**：

| 字段 | 值 |
|---|---|
| 接口地址 | `http://127.0.0.1:8317/v1`（关闭「自定义协议」） |
| 或完整路径 | `http://127.0.0.1:8317/v1/chat/completions`（开启「自定义协议」） |
| API Key | `wh-你的网关Key` |
| 模型名称 | `glm-5.3` |
| 能力标记 | **必须勾选「工具调用」**，否则 Agent 会退化成纯聊天 |

一个配置只能填一个模型名；要切换就多建几条（同一个 Key，不同模型名）。

### 6.4 Cursor / Cline / 任意 OpenAI SDK

- Base URL：`http://127.0.0.1:8317/v1`
- API Key：`wh-你的网关Key`
- Model：`/v1/models` 中的任一 `id`

### 6.5 MCP

网关自带 MCP 端点：`http://127.0.0.1:8317/mcp`，Header 带 `Authorization: Bearer wh-...`。
适用于支持远程 MCP 的客户端（Claude Desktop、Cline 等）。

---

## 7. 统一模型与故障转移（强烈建议）

一个「统一模型」= 一组跨平台 targets，前面的失败自动换后面的，客户端无感知。

后台 →「模型管理 → 统一模型」新建，例如 `agent-main`：

| 顺序 | 目标 | 策略 |
|---|---|---|
| 1 | trae / glm-5.3 | priority 10 |
| 2 | trae / kimi-k3.1-pro | priority 20 |
| 3 | workbuddy / hy4std | priority 30 |
| 4 | deepseek / deepseek-chat（官方 Key 兜底） | priority 40 |

策略可选：

- `priority`：严格按优先级，前面不可用才用后面（推荐）
- `weighted`：按权重随机，适合分摊额度
- `least_conn`：并发最少优先

之后所有客户端模型名统一填 `agent-main`，切换完全由网关完成。

**边界**：故障转移只发生在“上游还没开始输出”之前；已经流式吐字后中断不会重放（避免副作用重复）。

---

## 8. 自动签到

后台 →「设置 → 自动签到」：

- 开关 + 每日执行整点（默认 09:00）
- 服务启动后会补签当天未签的账号
- 幂等：已签到会识别为“今日已签”，不会重复请求

支持的平台：Trae、WorkBuddy、Qoder、千问办公。

**现实预期**：签到积分有限（每天几十积分级别），够“保活”，撑不住高频 Agent 任务。
WorkBuddy 若已提示 `14018 额度已用尽`，签到只能少量续命，建议同时接官方 API 兜底。

---

## 9. 管理 API 速查

Base：`http://127.0.0.1:8317`

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/admin/api/login` | `{"password":"..."}` → `{token}` |
| GET | `/admin/api/providers` | 平台列表、credFields、说明 |
| POST | `/admin/api/import-local-all` | 扫描本机并导入 |
| GET | `/admin/api/accounts` | 账号列表（状态/额度/模型数） |
| POST | `/admin/api/accounts` | 手动添加账号 |
| POST | `/admin/api/accounts/:id/checkin` | 单账号签到 |
| POST | `/admin/api/providers/:id/oauth/start` | 设备码授权 |
| POST | `/admin/api/providers/:id/oauth/poll` | 轮询授权结果 |
| POST | `/admin/api/refresh-models-all` | 同步全部模型 |
| POST | `/admin/api/apikeys` | 生成调用 Key |
| GET | `/admin/api/checkin/status` | 签到状态 |
| POST | `/admin/api/checkin/all` | 一键签到（全部账号） |
| GET/PUT | `/admin/api/settings/checkin` | 读取 / 修改自动签到配置（`{enabled,hour}`） |

调用侧（需要网关 Key）：

- `/v1/chat/completions`、`/v1/completions`、`/v1/embeddings`、`/v1/models`（OpenAI 兼容）
- `/v1/responses`（Codex / Responses API 客户端）
- `/v1/messages`、`/v1/messages/count_tokens`（Anthropic 兼容）
- `/mcp`（JSON-RPC over HTTP）

---

## 10. 排错对照表

| 现象 | 原因 | 处理 |
|---|---|---|
| `401 invalid api key` | Key 错/已吊销/含空格 | 后台重发，注意去掉首尾空格 |
| `404 model not found` | 模型名不在清单里（常见：填了 Claude 模型名） | 用 `/v1/models` 里的 id |
| `429` + `14018` | WorkBuddy 免费额度耗尽 | 签到/加量包/换模型/换账号 |
| `429` 其他 | 上游限流，账号进入 cooling | 等冷却；配统一模型自动切 |
| `no healthy account` | 全部账号失效或冷却 | 看账号状态，重新导入 |
| Claude Code 一直 404 | 没设 `ANTHROPIC_MODEL` | 按 6.1 配置 |
| WorkBuddy 扫描不到账号 | `$wbEncrypted` 加密信封 | 走 4.3 OAuth |
| 启动报端口占用 | 已有实例在跑 | 停旧实例，或 `WH_PORT=8318` |
| 模型列表里没有新账号的模型 | 没同步 | `refresh-models-all` |
| 账号显示 `wb-%0a` | 身份接口返回编码换行 | 仅显示问题，可改名 |

日志位置：`logs\`；数据库：`data\wharf.db`。

---

## 11. 安全与迁移

**必须知道的风险**

- `data/wharf.db` 里 **token 与 API Key 都是明文**：发人、上传网盘、提交 Git 前务必删除 `data/`
- 默认后台密码 `admin`：部署后第一件事就是改
- 默认监听 `0.0.0.0`：`start-gateway.ps1` 已改为 `127.0.0.1`，请勿改回，除非你清楚风险
- 自定义模型 / 网关 Key 一旦泄露，等于别人可以消耗你的额度：给每个客户端单独发 Key，并限制 `allowed_models` 与 `rpm_limit`
- 客户端型平台（Trae/WorkBuddy 等）的自动化接入可能违反其服务条款，存在封号风险，请自行评估

**迁移到另一台机器**

1. 复制整个 `modelwharf` 目录（含 `node_modules`，同架构可直接跑）
2. 如需保留账号，再复制 `data\wharf.db`
3. 新机启动后重新生成客户端 Key（旧 Key 也可继续用）

**升级**

覆盖 `src\`、`package.json`、`package-lock.json`，保留 `data\`，然后重启。
上游原始文档见 `README.upstream.md`、`AGENTS.upstream.md`。

---

## 12. 局域网集群部署（跨主机接入）

目标：**一台服务器跑 modelwharf，局域网内其他主机直接用 `http://<服务器IP>:8317` 接入**，
模型名统一填 `agent-main`，由网关接管整个集群的调度与故障转移。

```
其他主机（Claude Code / Codex / WorkBuddy / 脚本）
      │  http://<服务器IP>:8317/v1   model=agent-main
      ▼
 modelwharf 服务器（WH_HOST=0.0.0.0）
      ├─ /v1、/mcp  → 按 Key 鉴权，Key 锁定 agent-main
      └─ /admin     → 建议仅本机可访问
      ▼
 trae / workbuddy / 千帆 / 官方 Key（凭证只存在服务器）
```

> 本章只是部署方案，**不需要修改项目代码、不需要重新打包或推送**；
> 唯一的代码改动是 12.2 的可选安全补丁，不打也能跑。

### 12.1 必改五项（纯配置）

| 项 | 默认 | 改成 |
|---|---|---|
| 监听地址 | 默认仅本机 `127.0.0.1`（`start-gateway.ps1` 仅在未设时兜底） | 启动前设 `WH_HOST=0.0.0.0` |
| Windows 防火墙 | 拦截外部入站 | 放行 8317（仅专用网络） |
| 后台密码 | `admin` | 改强密码（面板或 `WH_ADMIN_PASSWORD`） |
| 自启方式 | 登录时启动 | 改开机启动，免登录也能被调用 |
| 调用 Key | 一把通用 | 每台主机一把，`allowed_models` 锁 `agent-main` |

```powershell
# 1) 防火墙（管理员 PowerShell）
New-NetFirewallRule -DisplayName "modelwharf 8317" -Direction Inbound `
  -Protocol TCP -LocalPort 8317 -Action Allow -Profile Private

# 2) 局域网模式启动
$env:WH_HOST="0.0.0.0"
powershell -ExecutionPolicy Bypass -File "C:\mysite\modelwharf\start-gateway.ps1"

# 3) 开机自启（免登录，管理员执行）
schtasks /Create /TN "modelwharf-gateway" /SC ONSTART /RL HIGHEST /F `
  /TR 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "$env:WH_HOST=''0.0.0.0''; & ''C:\mysite\modelwharf\start-gateway.ps1''"'

# 4) 给某台主机发 Key（只允许 agent-main）
POST /admin/api/apikeys
{"name":"host-02-claude","allowed_models":"agent-main","rpm_limit":60,"daily_limit":0}
```

### 12.2 可选安全补丁：/admin 仅本机

局域网模式下唯一建议的代码改动。在 `src/server.js` 里，
`app.use('/admin/api', adminRoutes);`（当前第 83 行）**之前**插入：

```js
app.use('/admin', (req, res, next) => {
  const ip = (req.ip || '').replace('::ffff:', '');
  if (ip === '127.0.0.1' || ip === '::1') return next();
  res.status(403).json({ error: 'admin is localhost only' });
});
```

插在这一行之前，`/admin/api`（admin REST）与 `/admin` 静态面板会同时被拦住；
插在之后则只拦住静态面板、REST 仍暴露，达不到效果。

效果：局域网主机只能调 `/v1`、`/mcp`，后台只能在服务器本机打开。
远程客户端的健康检查直接用 `GET /v1/models`（带 Key），返回 200 即链路正常。

### 12.3 客户端配置

| 客户端 | 配置 |
|---|---|
| Claude Code | `ANTHROPIC_BASE_URL=http://<服务器IP>:8317`、`ANTHROPIC_AUTH_TOKEN=<该机Key>`、`ANTHROPIC_MODEL=agent-main` |
| Codex CLI | `base_url="http://<服务器IP>:8317/v1"`、`model="agent-main"`、环境变量放该机 Key |
| WorkBuddy / Cursor | 自定义模型地址 `http://<服务器IP>:8317/v1`，模型名 `agent-main` |
| MCP 客户端 | `http://<服务器IP>:8317/mcp`，Header 带该机 Key |

调度策略（targets 顺序、新增平台）只在服务器面板改，全集群客户端自动生效。

### 12.4 边界与风险

- **接管的是请求，不是其他主机的客户端**。扫描本机凭证只读服务器自己的文件；
  其他电脑上的 Trae/WorkBuddy 无法被远程读取，要入池只能拿到 token 后手动添加到服务器。
- **凭证集中且明文**：所有账号 token 都在服务器的 `data/wharf.db`，
  服务器需管好登录口令、磁盘权限，且不要共享 `data/`。
- **HTTP 明文**：可信局域网内可接受；跨不可信网络必须套 HTTPS 反代（Caddy/Nginx），否则 Key 裸奔。
- **单点**：服务器宕机则全集群不可用，可用 12.5 的双网关互备缓解。

### 12.5 可选：跨主机双网关互备

第二台机器也部署 modelwharf 后，把它当作一个上游接入主机：

```
provider_id = openai-compat
baseUrl     = http://<第二台IP>:8317/v1
apiKey      = <第二台的Key>
```

再把它的模型追加到 `agent-main` 的 targets 末尾（priority 最大），
即可实现**跨主机兜底**：本机池子全失效时，自动落到另一台机器的额度。
