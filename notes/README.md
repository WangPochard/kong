# Kong 知識庫

所有 Kong 相關知識集中於此，避免分散。

## 文件索引

| 文件 | 內容 |
|------|------|
| [00-overview.md](00-overview.md) | 環境概覽、端口配置、架構圖 |
| [01-core-concepts.md](01-core-concepts.md) | Service / Route / Upstream / Consumer / Plugin |
| [02-admin-api.md](02-admin-api.md) | Admin API 速查、curl 技巧、declarative config |
| [03-plugins.md](03-plugins.md) | 各類 Plugin 設定（認證、限流、轉換、監控） |
| [04-setup.md](04-setup.md) | Docker Compose 操作、deck 工具、升版 |
| [05-troubleshooting.md](05-troubleshooting.md) | 常見問題診斷與排查 |
| [06-sso-oauth-integration.md](06-sso-oauth-integration.md) | SSO OAuth 流程 + Keycloak 代理 + Kong 路由配置 |

## 本地環境速查

- **Proxy**: `http://localhost:8000`
- **Admin API**: `http://localhost:8765`
- **Kong Manager**: `http://localhost:8002`
- **Config**: `/home/yisheng/kong/docker-compose.yml`

```bash
cd /home/yisheng/kong
docker compose up -d    # 啟動
docker compose down     # 關閉
docker compose logs -f kong  # 看 log
```

## Scripts

| Script | 說明 |
|--------|------|
| [`scripts/setup-sso-routes.sh`](../scripts/setup-sso-routes.sh) | 一鍵設置 SSO 的 Kong 路由、限流、CORS |

```bash
# 基本用法
./scripts/setup-sso-routes.sh

# 預覽（不執行）
./scripts/setup-sso-routes.sh --dry-run

# 清除重建
./scripts/setup-sso-routes.sh --clean

# 自訂環境變數
KONG_ADMIN=http://localhost:8765 \
SSO_UPSTREAM=http://sso-fhir:8000 \
CORS_ORIGINS="http://localhost:3000,https://prod.example.com" \
./scripts/setup-sso-routes.sh
```

## Plugin 速查

> 完整設定範例見 [03-plugins.md](03-plugins.md)

### 🔒 安全防護

| Plugin | 作用 | 掛載位置 | 本專案啟用狀況 |
|--------|------|---------|--------------|
| `cors` | 跨域請求控制，回應 OPTIONS 預檢 | 全域 / Service / Route | 全域啟用 |
| `ip-restriction` | IP 白名單 / 黑名單 | Route / Service | `sso-admin` Route |
| `rate-limiting` | 限制請求頻率，超過回 429 | Route / Service / 全域 | 多條 Route |

```bash
# 本專案的限流設定一覽
# sso-auth-login   ──  20次/分、200次/時（最嚴，防暴力破解）
# sso-auth-refresh ──  60次/分、500次/時
# sso-auth-misc    ──  10次/分、 50次/時（激活/忘密，防濫發信件）
# sso-admin        ──  IP 限制，只允許 172.25.0.0/16 + 127.0.0.1
# cors（全域）     ──  允許 Authorization、X-System-Ticket 等 header
```

---

### 🪪 認證

| Plugin | 適用場景 |
|--------|---------|
| `key-auth` | 簡單 API Key，適合機器對機器 |
| `jwt` | 驗 JWT 簽章（可搭配 Keycloak 公鑰） |
| `basic-auth` | 帳密驗證，適合內部工具 |
| `acl` | 搭配以上認證，再依 Consumer Group 授權 |

> 本專案目前未在 Kong 層掛認證 Plugin，JWT 驗證由 sso-fhir 後端自己處理。

---

### 🚦 流量控制

| Plugin | 作用 |
|--------|------|
| `rate-limiting` | 頻率限制（見安全防護） |
| `request-size-limiting` | 限制 Request Body 大小（單位 MB），防大檔案攻擊 |

---

### 🔄 轉換

| Plugin | 作用 |
|--------|------|
| `request-transformer` | 轉發前修改 Request（加 / 刪 / 改 Header、Query、Body） |
| `response-transformer` | 回傳前修改 Response Header |

---

### 📊 監控 / 日誌

| Plugin | 作用 |
|--------|------|
| `http-log` | 將請求 log 推送到外部 HTTP 端點 |
| `file-log` | 寫入本機檔案 |
| `prometheus` | 暴露 `/metrics` 端點供 Prometheus 抓取 |

---

## 新增筆記原則

- **每個主題一個文件**，不要混在一起
- 有實際測試過的指令才加入，加上預期結果
- 踩到的坑記錄在 `05-troubleshooting.md`
- 新設定的 Service/Plugin 組合記錄在 `06-recipes.md`（有需要再建）
