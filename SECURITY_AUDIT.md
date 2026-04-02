# 安全审计报告

**审计日期**: 2026-03-26  
**项目**: new-api  
**版本**: 基于 go 1.25+

---

## 1. 审计范围

- 后门代码检测
- 遥测/数据收集
- 敏感数据泄露风险
- 外部请求分析
- 认证与授权机制

---

## 2. 审计结论

### ✅ 未发现后门代码

代码中没有发现后门或恶意代码。所有外部 HTTP 请求都是功能性请求：

| 请求类型 | 目标 | 用途 |
|---------|------|------|
| OAuth 提供者 | github.com, discord.com, connect.linux.do 等 | 用户身份认证 |
| AI 渠道请求 | api.openai.com, api.anthropic.com 等 57+ 提供商 | AI API 代理转发 |
| 价格同步 | basellm.github.io, models.dev | 模型价格配置同步 |
| 支付处理 | stripe.com, creem.io 等 | 充值支付 |

---

## 3. 遥测与分析功能

以下功能**默认禁用**，需管理员显式配置环境变量才会启用：

### 3.1 Umami Analytics（前端访问统计）

- **触发条件**: 设置 `UMAMI_WEBSITE_ID` 环境变量
- **代码位置**: `main.go:201-217`
- **数据接收方**: `https://analytics.umami.is/script.js` 或自定义 URL
- **风险等级**: ℹ️ 低

```go
// main.go
if os.Getenv("UMAMI_WEBSITE_ID") != "" {
    umamiScriptURL = os.Getenv("UMAMI_SCRIPT_URL")
    if umamiScriptURL == "" {
        umamiScriptURL = "https://analytics.umami.is/script.js"
    }
}
```

### 3.2 Google Analytics（前端访问统计）

- **触发条件**: 设置 `GOOGLE_ANALYTICS_ID` 环境变量
- **代码位置**: `main.go:220-239`
- **数据接收方**: `https://www.googletagmanager.com`
- **风险等级**: ℹ️ 低

### 3.3 Pyroscope（性能分析）

- **触发条件**: 设置 `PYROSCOPE_URL` 环境变量
- **代码位置**: `common/pyro.go`
- **数据类型**: CPU profile, 内存分配, Goroutine 等
- **风险等级**: ⚠️ 中（性能数据会发送到外部服务器）

```go
// common/pyro.go
pyroscopeUrl := GetEnvOrDefaultString("PYROSCOPE_URL", "")
if pyroscopeUrl == "" {
    return nil  // 默认不启用
}
```

### 3.4 pprof 调试端点

- **触发条件**: 设置 `ENABLE_PPROF=true`
- **代码位置**: `main.go:141-146`
- **监听地址**: `0.0.0.0:8005`
- **风险等级**: ⚠️ 中（生产环境应禁用）

```go
// main.go
if os.Getenv("ENABLE_PPROF") == "true" {
    gopool.Go(func() {
        log.Println(http.ListenAndServe("0.0.0.0:8005", nil))
    })
}
```

---

## 4. 敏感数据保护

### 4.1 API 响应过滤

以下配置项**不会返回给前端**：

```go
// controller/option.go:70-73
if strings.HasSuffix(k, "Token") ||
   strings.HasSuffix(k, "Secret") ||
   strings.HasSuffix(k, "Key") ||
   strings.HasSuffix(k, "secret") ||
   strings.HasSuffix(k, "api_key") {
    continue  // 跳过，不返回
}
```

### 4.2 数据库字段保护

| 字段类型 | 保护方式 | 代码位置 |
|---------|---------|---------|
| 用户密码 | bcrypt 哈希 | `common/crypto.go` |
| TOTP 密钥 | `json:"-"` 标签 | `model/twofa.go:19` |
| OAuth ClientSecret | `json:"-"` 标签 | `model/custom_oauth_provider.go:47` |
| API Keys | 日志中脱敏 | `common/str.go:181-183` |

### 4.3 URL 脱敏示例

```go
// common/str.go
// https://api.test.org/v1/users/123?key=secret
// -> https://***.org/***/***/?key=***
```

---

## 5. 认证与授权机制

### 5.1 支持的认证方式

- **Session 认证**: 基于 cookie 的会话管理
- **Token 认证**: Bearer Token / API Key
- **2FA 双因素认证**: TOTP + 备用码
- **Passkey/WebAuthn**: 无密码认证
- **OAuth**: GitHub, Discord, LinuxDo, OIDC 等

### 5.2 权限控制

```go
// middleware/auth.go
- RoleCommonUser  // 普通用户
- RoleAdminUser   // 管理员
- RoleRootUser    // 超级管理员
```

### 5.3 Token 安全特性

- Token IP 白名单限制
- Token 过期时间控制
- Token 模型访问限制
- Token 额度控制

---

## 6. 外部请求清单

### 6.1 OAuth 提供者

| 提供者 | 端点 |
|-------|------|
| GitHub | `github.com`, `api.github.com` |
| Discord | `discord.com` |
| LinuxDo | `connect.linux.do` |
| OIDC | 用户配置 |

### 6.2 AI 提供商（部分）

| 提供商 | API 端点 |
|-------|---------|
| OpenAI | `api.openai.com` |
| Anthropic | `api.anthropic.com` |
| Google | `generativelanguage.googleapis.com` |
| AWS Bedrock | `bedrock-runtime.*.amazonaws.com` |
| Azure | 用户配置 |
| 智谱 | `open.bigmodel.cn` |
| 月之暗面 | `api.moonshot.cn` |
| DeepSeek | `api.deepseek.com` |
| ... | 共 57+ 提供商 |

### 6.3 配置同步

| 用途 | 端点 |
|-----|------|
| 官方价格预设 | `basellm.github.io` |
| models.dev 价格 | `models.dev/api.json` |
| 模型元数据 | `basellm.github.io/llm-metadata` |

---

## 7. 生产环境建议

### 7.1 必须禁用

```bash
# 不要设置以下环境变量
ENABLE_PPROF=true          # pprof 调试端点
```

### 7.2 按需启用

```bash
# 根据需要决定是否启用
UMAMI_WEBSITE_ID=xxx       # 前端访问统计
GOOGLE_ANALYTICS_ID=G-xxx  # Google Analytics
PYROSCOPE_URL=http://xxx   # 性能分析（自建服务器）
```

### 7.3 必须配置

```bash
# 安全相关配置
SESSION_SECRET=<随机字符串>  # 会话密钥
CRYPTO_SECRET=<随机字符串>   # 加密密钥
```

---

## 8. 审计总结

| 检查项 | 结果 |
|-------|------|
| 后门代码 | ✅ 未发现 |
| 恶意外部请求 | ✅ 未发现 |
| 敏感数据泄露 | ✅ 已保护 |
| 认证机制 | ✅ 完善 |
| 遥测功能 | ⚠️ 可选，默认禁用 |
| 调试端点 | ⚠️ 可选，默认禁用 |

**总体评价**: 代码安全性良好，敏感数据保护到位，遥测和分析功能均为可选配置。
