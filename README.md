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
| `WH_HOST` | `0.0.0.0`（脚本内已改为 `127.0.0.1`） | 监听地址，**建议保持 127.0.0.1** |
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
   POST /admin/api/providers/workbuddy/oauth/start   → {state, authUrl}
   ```
2. 打开返回的 `authUrl`（形如 `https://copilot.tencent.com/login?platform=CLI&state=<uuid>`），
   用 **WorkBuddy 账号**登录并确认授权
3. 轮询直到 `pending=false`：
   ```powershell
   POST /admin/api/providers/workbuddy/oauth/poll   body {"state":"<uuid>"}
   ```

**路线 B：抓包（拿不到 refreshToken，约 1 个月重抓一次）**

1. 浏览器打开 `https://copilot.tencent.com` 并登录
2. F12 → Network → 任一接口请求 → 复制请求头 `Authorization: Bearer xxx`
3. 后台手动添加账号，粘贴 token；有 `X-Device-Token` 一并填

CredFields：`token`（必填）、`refreshToken`、`userId`、`xDeviceToken`、`region`（默认 `cn`）。

**常见状态**

- `cooling` + `code 14018 额度已用尽` → 免费积分耗尽，等签到/购买加量包
- 账号名显示 `wb-%0a` 只是身份接口返回了 URL 编码换行，功能不受影响

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
