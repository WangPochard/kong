# SSO OAuth 整合 Kong 設定

> ⚠️ 本文件從 `~/sso-fhir` 原始碼讀取後撰寫，所有路由、請求格式、回應格式均與實作一致。

---

## 系統架構

```
外部流量
   │
   ▼
 Kong (80/443 對外)
   │
   ▼ 路由至
 SSO FastAPI (內部 container:8000)
   │
   ├─ JWT 驗證 → Keycloak JWKS (內部 :8080/realms/{realm}/protocol/openid-connect/certs)
   ├─ Token 撤銷 → Valkey (DB 1)
   └─ Token Exchange → Keycloak Admin API (內部)

子系統 Backend（若在同一 Docker network）
   └─ 直接打 http://sso-fhir:8000（不過 Kong）
```

**原則：Keycloak 永遠不對外，SSO 是唯一代理。**

---

## 認證類型：ROPC（非 Authorization Code）

這個 SSO **不是** OAuth2 Authorization Code / PKCE 流程。
前端直接送帳密給 SSO，SSO 對 Keycloak 做 ROPC，再回傳 token。

```
Browser ──POST── /api/sso/auth/login {username, password, cap_token?}
   │
   └─► SSO → Keycloak (ROPC, 內部)
              ↓
         SSO 回傳 {access_token, refresh_token, expires_in}
              ↓
         Browser 存 token，後續請求帶 "Authorization: Bearer {access_token}"
```

---

## 完整 API 路由表

所有路由前綴皆為 `/api/sso/`。

### 認證路由（`/api/sso/auth/`）

| 方法 | 路徑 | Auth | 說明 |
|------|------|------|------|
| POST | `/api/sso/auth/login` | 無 | 登入，取得 access_token + refresh_token |
| POST | `/api/sso/auth/refresh` | 無 | 用 refresh_token 刷新 access_token |
| POST | `/api/sso/auth/logout` | Bearer | 撤銷 token（Valkey + DB + Keycloak） |
| POST | `/api/sso/auth/verify-act-token` | 無 | 驗證帳號激活 token |
| POST | `/api/sso/auth/activate` | 無 | 完成帳號激活 + 設密碼（此時才建 Keycloak 帳號） |
| POST | `/api/sso/auth/forget-password/email-otp` | 無 | 忘記密碼：發送 Email OTP |
| POST | `/api/sso/auth/forget-password/otp-verify` | 無 | 忘記密碼：驗證 OTP，取得 reset token |
| POST | `/api/sso/auth/forget-password/reset` | 無 | 忘記密碼：用 reset token 設新密碼 |

### 個人資料（`/api/sso/users/me`）

| 方法 | 路徑 | Auth | 說明 |
|------|------|------|------|
| GET  | `/api/sso/users/me` | Bearer | 取得個人資料 |
| PUT  | `/api/sso/users/me` | Bearer | 更新個人資料 |
| POST | `/api/sso/users/me/change-password` | Bearer | 修改密碼 |
| GET  | `/api/sso/users/me/systems` | Bearer | 查詢我可存取的子系統清單 |

### 管理員（`/api/sso/admin/accounts`）

| 方法 | 路徑 | Auth | 說明 |
|------|------|------|------|
| GET  | `/api/sso/admin/accounts` | Bearer + admin | 查詢所有使用者 |
| POST | `/api/sso/admin/accounts` | Bearer + admin | 建立使用者（pre-register，寄激活信） |
| * | `/api/sso/admin/accounts/{id}/*` | Bearer + admin | 個別使用者操作 |

### 子系統串接（`/api/sso/systems/`）— 重點

#### 使用者流程（3 步驟）

**步驟 1/3：取得進入授權碼（由主系統前端呼叫）**

```
POST /api/sso/systems/{system_id}/entry-code
Authorization: Bearer {使用者的 access_token}
```

回傳：**HTTP 302 Redirect** 到 `{subsystem.base_url}?code={entry_code}`

> ⚠️ 不是 JSON！Kong 必須讓 302 穿透，不能自動 follow redirect。

授權碼特性：
- `secrets.token_urlsafe(32)` 生成，長度 43 字元
- 60 秒有效（`ENTRY_CODE_TTL_SECONDS = 60`）
- 單次使用（`is_used = True` 後即無效）
- `access_token` 存在 DB（`EntryCode.access_token`），**子系統永遠拿不到原始 token**

**步驟 2/3：子系統驗證授權碼並換取 Token（由子系統 Backend 呼叫）**

```
POST /api/sso/systems/verify
X-System-Ticket: {subsystem_client_secret}     ← header，不是 body
Content-Type: application/json

{
  "system_id": "lis-system",
  "code": "{entry_code from URL}"
}
```

回傳：
```json
{
  "message": "驗證成功",
  "data": {
    "active": true,
    "exchanged_token": "eyJhbGciOiJSUzI1NiJ9...",
    "token_type": "Bearer",
    "expires_in": 300
  }
}
```

驗證邏輯（兩層）：
1. `X-System-Ticket` → SHA256 hash → 比對 DB `client_secret_hash`
2. `code` → 查 DB EntryCode，確認未過期、未使用、`system_id` 吻合

兩層全通過後：以 DB 中存的 `access_token` 對 Keycloak 做 Token Exchange，
回傳帶有子系統 `audience` 的新 JWT（`exchanged_token`）。

**步驟 3/3：查詢使用者即時狀態（子系統選用）**

```
GET /api/sso/systems/userinfo
X-Exchange-Token: {exchanged_token}
```

回傳：
```json
{
  "data": {
    "user": {
      "sub": "kc-user-uuid",
      "username": "doctor01",
      "email": "doctor01@hospital.com",
      "role_code": "doctor",
      "is_active": true
    },
    "organization": {
      "id": 1,
      "name": "台北榮總",
      "subscription_active": true
    }
  }
}
```

驗證流程：從 Keycloak JWKS 驗 JWT 簽章 + exp → 從 `aud` 找子系統 → 從 `sub` 找使用者 → 查撤銷記錄。

#### M2M 流程（背景子系統，無使用者）

```
POST /api/sso/systems/client-token
Content-Type: application/json

{
  "client_id": "lis-system",
  "client_secret": "{明文 secret，SSO 會 hash 後比對}"
}
```

回傳 Keycloak Service Account Token（sub = `service-account-{client_id}`）。

---

## 安全機制

### 漸進式登入鎖定

| 失敗次數 | 行為 | 鎖定時間 |
|---------|------|---------|
| 0–4 次  | 正常（可能要求 CAPTCHA） | — |
| 5 次 / 第 1 輪 | 鎖定 | 1 分鐘 |
| 5 次 / 第 2 輪 | 鎖定 | 5 分鐘 |
| 5 次 / 第 3 輪 | 鎖定 | 15 分鐘 |
| 5 次 / 第 4 輪 | 鎖定 | 60 分鐘 |
| 5 次 / 第 5 輪+ | 鎖定 | 240 分鐘 |

CAPTCHA：`LOGIN_CAPTCHA_THRESHOLD` 設定觸發門檻，超過後 `cap_token` 必填。

### Token 撤銷架構

```
logout → 1. Valkey (DB 1) 寫入撤銷名單，TTL = token 剩餘有效秒數  ← 快速擋
         2. DB RevokedToken 寫入（稽核用）
         3. Keycloak logout(refresh_token)（讓 refresh 失效）

驗證時 → is_token_revoked(hash):
           True  → Valkey 明確說已撤銷 → 拒絕
           False → 未撤銷 → 通過
           None  → Valkey 不可用 → fallback 查 DB
```

### client_secret 安全

- Keycloak 生成的 `client_secret` **從不明文存 DB**
- 存 `SHA256(client_secret)` 到 `SubsystemRegistry.client_secret_hash`
- 子系統每次送明文，SSO hash 後比對
- Secret 只在 `POST /api/sso/systems/register` 回傳一次，之後無法查詢

### Swagger UI 保護

- 路徑 `/docs`, `/redoc`, `/openapi.json` 全部受 HTTP Basic Auth 保護
- 憑證來自 `SWAGGER_USERNAME` / `SWAGGER_PASSWORD` 環境變數

---

## Kong 配置（針對此 SSO 架構）

### 路由設計原則

| 呼叫者 | 目標端點 | 走 Kong？ | 理由 |
|-------|---------|----------|------|
| Browser / 主系統前端 | `/api/sso/auth/*` | ✅ | 外部流量 |
| Browser / 主系統前端 | `/api/sso/systems/{id}/entry-code` | ✅ | 外部流量，回傳 302 |
| 子系統 Backend（同 Docker）| `/api/sso/systems/verify` | ❌ 直連 | server-to-server，不走公網 |
| 子系統 Backend（同 Docker）| `/api/sso/systems/userinfo` | ❌ 直連 | 同上 |
| 子系統 Backend（同 Docker）| `/api/sso/systems/client-token` | ❌ 直連 | M2M，不走公網 |
| 子系統 Backend（跨主機）| `/api/sso/systems/verify` | ✅（加 IP 限制） | 需過 Kong，但限制 IP |

### Declarative Config（kong.yml）

```yaml
_format_version: "3.0"

services:
  - name: sso-fhir
    url: http://sso-fhir:8000        # Docker 內部 hostname（container_name）
    connect_timeout: 5000
    read_timeout: 60000              # activate 可能較慢（建 Keycloak 帳號）
    write_timeout: 60000

    routes:
      # ── 登入（最高優先度，要限流）──
      - name: sso-auth-login
        paths: ["/api/sso/auth/login"]
        methods: ["POST", "OPTIONS"]
        strip_path: false

      - name: sso-auth-refresh
        paths: ["/api/sso/auth/refresh"]
        methods: ["POST", "OPTIONS"]
        strip_path: false

      - name: sso-auth-logout
        paths: ["/api/sso/auth/logout"]
        methods: ["POST", "OPTIONS"]
        strip_path: false

      # ── 帳號激活 / 忘記密碼（無 auth 保護，需限流）──
      - name: sso-auth-misc
        paths: ["/api/sso/auth"]
        methods: ["GET", "POST", "OPTIONS"]
        strip_path: false

      # ── 個人資料（需 Bearer）──
      - name: sso-users-me
        paths: ["/api/sso/users"]
        methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
        strip_path: false

      # ── Admin（需 Bearer + admin role，加 IP 限制）──
      - name: sso-admin
        paths: ["/api/sso/admin"]
        methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
        strip_path: false

      # ── 子系統 entry-code（回傳 302，需 Bearer）──
      - name: sso-systems-entry-code
        paths: ["/api/sso/systems"]
        methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
        strip_path: false

      # ── Health check ──
      - name: sso-health
        paths: ["/api/sso/health", "/api/sso"]
        methods: ["GET"]
        strip_path: false

plugins:
  # 登入限流（搭配 Valkey）
  - name: rate-limiting
    route: sso-auth-login
    config:
      minute: 20
      hour: 200
      policy: redis
      redis:
        host: cap-valkey
        port: 6379
        database: 2              # 避開 SSO 用的 DB 0 和 DB 1

  # Refresh 限流
  - name: rate-limiting
    route: sso-auth-refresh
    config:
      minute: 60
      policy: redis
      redis:
        host: cap-valkey
        port: 6379
        database: 2

  # 激活 / 忘記密碼限流
  - name: rate-limiting
    route: sso-auth-misc
    config:
      minute: 10
      policy: redis
      redis:
        host: cap-valkey
        port: 6379
        database: 2

  # Admin 路由 IP 限制（只允許內部網段）
  - name: ip-restriction
    route: sso-admin
    config:
      allow:
        - 172.25.0.0/16          # SSO Docker 網段
        - 127.0.0.1              # localhost

  # CORS（全域）
  - name: cors
    config:
      origins:
        - "http://localhost:3000"
        - "https://your-frontend.com"
      methods: ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]
      headers:
        - "Authorization"
        - "Content-Type"
        - "X-System-Ticket"
        - "X-Exchange-Token"
        - "X-Requested-With"
      credentials: true
      max_age: 3600
```

> **302 Redirect 注意**：`/api/sso/systems/{id}/entry-code` 回傳 302，Kong 預設會穿透（不 follow），Browser 會跟隨。這是正確行為，**不需要特別設定**。

---

## 帳號激活流程（含 Keycloak 建立時機）

```
1. 管理員 POST /api/sso/admin/accounts
   → DB 建立 User（is_active=False, keycloak_user_id=NULL）
   → 寄激活信（含 activation_token）

2. 使用者點信件連結
   POST /api/sso/auth/verify-act-token { "token": "..." }
   → email_verified = True

3. 使用者設定密碼
   POST /api/sso/auth/activate { "token": "...", "password": "..." }
   → 呼叫 Keycloak API 建立帳號（此時才有 keycloak_user_id）
   → is_active = True
```

---

## 子系統完整接入流程

### 第一次接入（管理員操作）

```bash
# 向 SSO 註冊新子系統（SSO 自動在 Keycloak 建 client + Token Exchange 設定）
POST /api/sso/systems/register
Authorization: Bearer {admin_token}
{
  "system_id": "lis-system",
  "name": "檢驗資訊系統",
  "base_url": "http://lis.hospital.com"
}

# 回傳（僅此一次）：
# {
#   "client_secret": "xxxx-xxxx",  ← 子系統妥善保存，之後查不到
#   ...
# }
```

### 使用者進入子系統（Runtime）

```
1. 主系統前端（已登入，有 access_token）：
   POST /api/sso/systems/lis-system/entry-code
   → 302 redirect 到 http://lis.hospital.com?code=ABC123

2. 子系統 Frontend：
   拿到 ?code=ABC123，傳給子系統 Backend

3. 子系統 Backend（直連 SSO 內部）：
   POST http://sso-fhir:8000/api/sso/systems/verify
   X-System-Ticket: {lis-system 的 client_secret}
   { "system_id": "lis-system", "code": "ABC123" }
   → 取得 exchanged_token

4. 子系統 Backend（選用）：
   GET http://sso-fhir:8000/api/sso/systems/userinfo
   X-Exchange-Token: {exchanged_token}
   → 取得使用者資料 + 機關訂閱狀態
```

---

## 快速診斷指令

```bash
SSO_HOST="http://localhost:8000"   # 若透過 Kong: http://localhost:8000
ADMIN_API="http://localhost:8765"  # Kong Admin API

# ── SSO 健康狀態 ──
curl -s $SSO_HOST/api/sso/health | jq .

# ── 登入取得 token ──
curl -s -X POST $SSO_HOST/api/sso/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"your_password"}' | jq .

# ── 確認 Kong 路由 ──
curl -s $ADMIN_API/routes | jq '.data[].name'

# ── 確認 Kong rate-limiting plugin ──
curl -s $ADMIN_API/plugins | jq '.data[] | select(.name=="rate-limiting") | {route_id, config}'
```
