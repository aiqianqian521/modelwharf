# AGENTS.md — 让任何 Agent 接入本网关

> 本文件是给 **AI Agent** 读的操作契约，不是给人看的说明书。
> 人看的部署/客户端配置见 `README.md`；可直接复制的话术见 `PROMPTS.md`。

---

## 0. 事实（不要猜，以此为准）

| 项 | 值 |
|---|---|
| 网关地址 | `http://127.0.0.1:8317` |
| 管理后台 | `http://127.0.0.1:8317/admin`（默认密码 `admin`，可能已被改） |
| 管理 API 鉴权 | `POST /admin/api/login {"password":"..."}` → `{token}`，之后 `Authorization: Bearer <token>` |
| 调用 API 鉴权 | `Authorization: Bearer <网关Key，wh- 开头>` |
| 数据库 | `data/wharf.db`（SQLite，**明文凭证**） |
| 版本 | 0.13.1 |

接口能力：OpenAI 兼容 `/v1/chat/completions`、`/v1/models`、`/v1/completions`、`/v1/embeddings`；
Responses API `/v1/responses`；Anthropic 兼容 `/v1/messages`；MCP `/mcp`。

---

## 1. 接入账号（标准流程）

```
1) 登录管理 API 拿 token
2) GET  /admin/api/providers            确认目标平台在列，读 credFields / 说明
3) POST /admin/api/import-local-all     先试自动扫描（能解密的会直接导入）
4) 扫不到时按平台分支处理：
   · 有 oauth 支持 → POST /admin/api/providers/<id>/oauth/start 拿 authUrl，
     把 authUrl 原样交给用户完成登录，再 POST .../oauth/poll {"state":"..."} 直到 pending=false
   · 无 oauth      → 让用户抓包提供 token，再 POST /admin/api/accounts 手动添加
5) POST /admin/api/refresh-models-all   必须执行，否则模型列表缺失
6) 验证：POST /v1/chat/completions 发最小请求（要求只回复 OK）
7) 汇报：账号名、uid 后 4 位、导入模型数、验证结果
```

### 1.1 平台分支要点

**trae（字节）**
- 本地 `%APPDATA%\Trae CN\User\globalStorage\storage.json` → `iCubeAuthInfo://icube.cloudide`
- AES-128-CBC 加密，网关内置解密 → 优先直接 `import-local-all`
- 想要第二个账号：让用户在 Trae 客户端切号，然后重新扫描（按 uid 去重，不叠加）
- 字段：`token`(必填)、`refreshToken`、`uid`、`region`(cn/intl)

**workbuddy（腾讯 WorkBuddy / CodeBuddy）**
- 本地文件是 `{"$wbEncrypted":1,"envelope":"..."}`，**不可解密，不要尝试破解**
- 扫描器会把该项**永久加入排除名单**并返回原因，这是预期行为，不要反复重扫
- 唯一正规路径：`POST /admin/api/providers/workbuddy/oauth/start` → 用户登录
  `https://copilot.tencent.com/login?platform=CLI&state=<uuid>` → `oauth/poll`
- 备选：用户在 `copilot.tencent.com` 网页登录后，从请求头取 `Authorization: Bearer ...`
  与可选 `X-Device-Token`，手动 `POST /admin/api/accounts`
- 字段：`token`(必填)、`refreshToken`、`userId`、`xDeviceToken`、`region`
- `code 14018` = 额度用尽，不是配置错误

**qoder / qodercn / qwen / qwenwork**
- 先扫描；再查 providers 返回的 credFields 与 docs
- `qwenwork` 的 refreshToken 每次刷新轮换，必须由网关写回

**官方 API（deepseek / zhipu / moonshot / dashscope / doubao / openrouter / openai-compat 等）**
- 直接 `POST /admin/api/accounts {provider_id, credentials:{apiKey}}`
- `openai-compat` 需要 `baseUrl` + `apiKey`

**豆包**
- 内置 `doubao` 指的是火山方舟官方 API Key，**不是豆包客户端登录态**
- 想用客户端额度：需额外部署 doubao2api（默认 :9090），再以 `openai-compat` 接入
- 必须向用户说明走的是哪条路线、额度归属谁

---

## 2. 给客户端发 Key

```http
POST /admin/api/apikeys
{"name":"claude-code","allowed_models":["glm-5.3"],"rpm_limit":60,"daily_limit":2000}
```

返回的 `key` 形如 `wh-...`，交给目标客户端使用。

---

## 3. 客户端接入参数（可直接照抄）

| 客户端 | 配置 |
|---|---|
| Claude Code | `settings.json` → `env.ANTHROPIC_BASE_URL=http://127.0.0.1:8317`、`ANTHROPIC_AUTH_TOKEN=wh-...`、**`ANTHROPIC_MODEL=<模型id>` 必填**、`ANTHROPIC_SMALL_FAST_MODEL=<小模型>` |
| Codex CLI | `config.toml`：`base_url="http://127.0.0.1:8317/v1"`、`env_key="MODELWHARF_API_KEY"`，并设同名环境变量为 `wh-...` |
| WorkBuddy | 自定义模型：地址 `http://127.0.0.1:8317/v1`（或开“自定义协议”填全路径 `/v1/chat/completions`）、Key `wh-...`、模型名、**勾选工具调用** |
| Cursor / Cline / SDK | Base URL `http://127.0.0.1:8317/v1`，Key `wh-...`，模型名取 `/v1/models` 的 `id` |
| MCP 客户端 | `http://127.0.0.1:8317/mcp`，Header `Authorization: Bearer wh-...` |

模型名必须与 `/v1/models` 返回的 `id` 完全一致。Claude/Codex 的默认模型名在网关里不存在，必须显式覆盖。

---

## 4. 故障转移（建议主动配置）

```
POST /admin/api/virtual-models
{"public_name":"agent-main","strategy":"priority","targets":[
  {"provider_id":"trae","public_name":"glm-5.3","priority":10},
  {"provider_id":"trae","public_name":"kimi-k3.1-pro","priority":20},
  {"provider_id":"workbuddy","public_name":"hy4std","priority":30}
]}
```

target 字段固定为 `{provider_id, public_name, priority, weight}`：
`priority` 升序优先尝试；`weight` 仅用于 `weighted` 策略。
多账号平台可用 `模型@账号别名` 把目标锁定到具体账号（先 `GET /admin/api/virtual-models/targets` 看可用值）。
之后客户端模型名统一填 `agent-main`。
策略：`priority`（默认）/ `weighted` / `least_conn`。
切换只发生在“上游尚未输出”之前；流式开始后中断不会重放。

---

## 5. 硬性约束（违反即失败）

1. 只在 `127.0.0.1` 内操作；不得把 token / Key 发往任何外部地址或第三方服务
2. **不得在对话、日志、代码中打印完整 token 或完整 Key**，只显示后 4 位
3. 只读客户端文件，不修改、不删除 Trae / WorkBuddy 等客户端的数据
4. 加密信封（`$wbEncrypted`）直接放弃解密，走授权流程
5. 每步失败先停下说明原因，不要用同一动作反复重试
6. 导入账号后必须 `refresh-models-all`，并发真实请求验证，不能只凭“导入成功”下结论

---

## 6. 给不同类型的 Agent 的话术

### 6.1 通用（本地 Agent：Claude Code / Codex CLI / WorkBuddy 桌面）

```text
【任务】把本机某个 AI 客户端的登录态接入本地网关 modelwharf。

【已知事实】
- 网关：http://127.0.0.1:8317，管理密码 admin（可能已被修改，先问用户）
- 管理 API（先 POST /admin/api/login 取 token，之后 Bearer）：
  GET /admin/api/providers ｜ POST /admin/api/import-local-all ｜
  POST /admin/api/accounts ｜ POST /admin/api/providers/<id>/oauth/start ｜
  POST /admin/api/providers/<id>/oauth/poll ｜ POST /admin/api/refresh-models-all ｜
  POST /admin/api/apikeys ｜ POST /admin/api/checkin/status

【顺序】
1. 登录并列出平台，确认支持的目标平台与其 credFields
2. 先跑 import-local-all（成本最低）
3. 扫不到：有 OAuth 就走设备码（把 authUrl 原样给我，我登录完你再 poll）；没有就让我抓包提供 token
4. refresh-models-all
5. 用最小请求验证，确认返回正常
6. 汇报账号名、uid 后 4 位、模型数、验证结果

【约束】只在本机操作；不打印完整 token/Key；只读客户端文件；失败即停，不重复重试。
```

### 6.2 WorkBuddy 专用

```text
【目标】provider_id = workbuddy
【已知】本地 workbuddy-desktop.info 是 $wbEncrypted 加密信封，不可解密。
【做法】POST /admin/api/providers/workbuddy/oauth/start → 把 authUrl 给我 →
我登录后你 POST .../oauth/poll {"state":"<uuid>"} 直到 pending=false →
refresh-models-all → 最小请求验证。
【备选】我在 copilot.tencent.com 抓 Authorization: Bearer 给你，你 POST /admin/api/accounts。
【注意】code 14018 = 额度用尽，不是配置问题。
```

### 6.3 云端 Agent（不能访问本机文件 / 127.0.0.1）

```text
【约束】你无法访问我的文件系统与 127.0.0.1。
【请只做】输出抓包指引：打开哪个网址、在开发者工具看哪个请求、复制哪个请求头、
对应 modelwharf 的哪个 credField。由我在本地填入。
【禁止】不要索要 token 以外的凭据，不要建议把 token 发到公网。
```

---

## 7. 完成判据（缺一不可）

- [ ] 目标账号在 `GET /admin/api/accounts` 中 `status=active`（或说明为何 cooling）
- [ ] `refresh-models-all` 执行后能看到该账号的模型
- [ ] `POST /v1/chat/completions` 返回 200 且有内容
- [ ] 已生成独立 `wh-` Key 并交付给用户（只显示后 4 位）
