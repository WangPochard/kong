# Kong 核心概念

## Service

代表一個 upstream API。Kong 收到請求後，依照 Route 匹配，將流量轉發到對應的 Service。

```bash
# 建立 Service（直接指向 upstream URL）
curl -X POST http://localhost:8765/services \
  -d name=my-api \
  -d url=http://backend-host:8000

# 建立 Service（分開設定 host/port/path）
curl -X POST http://localhost:8765/services \
  -d name=my-api \
  -d protocol=http \
  -d host=backend-host \
  -d port=8000 \
  -d path=/api

# 列出所有 Services
curl http://localhost:8765/services

# 查詢單一 Service
curl http://localhost:8765/services/my-api

# 刪除
curl -X DELETE http://localhost:8765/services/my-api
```

**重要欄位：**
- `name` — 唯一識別，可用於之後的 API path
- `url` — 快速設定（展開為 protocol + host + port + path）
- `connect_timeout` / `read_timeout` / `write_timeout` — 預設 60000ms

---

## Route

定義哪些請求要被導向某個 Service。一個 Service 可以有多條 Route。

```bash
# 建立 Route（依 path 匹配）
curl -X POST http://localhost:8765/services/my-api/routes \
  -d name=my-api-route \
  -d "paths[]=/v1/my-api"

# 建立 Route（依 host 匹配）
curl -X POST http://localhost:8765/services/my-api/routes \
  -d name=my-api-host-route \
  -d "hosts[]=api.example.com"

# 建立 Route（path + method）
curl -X POST http://localhost:8765/services/my-api/routes \
  -d name=my-api-get-route \
  -d "paths[]=/v1/my-api" \
  -d "methods[]=GET" \
  -d "methods[]=POST"

# 列出所有 Routes
curl http://localhost:8765/routes

# 刪除
curl -X DELETE http://localhost:8765/routes/my-api-route
```

**匹配優先順序：** `hosts` > `paths` > `methods` > `headers`

**`strip_path`：**
- `true`（預設）：`/v1/my-api/users` 轉發到 upstream 時變成 `/users`
- `false`：完整路徑轉發

---

## Upstream & Target

用於負載均衡。Service 的 `host` 指向 Upstream 名稱，Upstream 再分配流量到多個 Target。

```bash
# 建立 Upstream
curl -X POST http://localhost:8765/upstreams \
  -d name=my-api-upstream

# 加入 Target（預設 weight=100）
curl -X POST http://localhost:8765/upstreams/my-api-upstream/targets \
  -d target=backend1:8000 \
  -d weight=100

curl -X POST http://localhost:8765/upstreams/my-api-upstream/targets \
  -d target=backend2:8000 \
  -d weight=50

# Service 指向 Upstream
curl -X PATCH http://localhost:8765/services/my-api \
  -d host=my-api-upstream

# 查看 Upstream 的 active targets
curl http://localhost:8765/upstreams/my-api-upstream/targets/all
```

**演算法：** `round-robin`（預設）、`least-connections`、`consistent-hashing`

---

## Consumer

代表一個 API 使用者（人或服務）。用於 per-consumer 的認證或限流。

```bash
# 建立 Consumer
curl -X POST http://localhost:8765/consumers \
  -d username=alice \
  -d custom_id=user-123

# 列出所有 Consumers
curl http://localhost:8765/consumers

# 為 Consumer 設定 API Key
curl -X POST http://localhost:8765/consumers/alice/key-auth \
  -d key=my-secret-key

# 為 Consumer 設定 JWT
curl -X POST http://localhost:8765/consumers/alice/jwt
```

---

## Plugin

掛載認證、限流、日誌等功能。可以掛在四個層級：

| 層級 | 範圍 |
|------|------|
| Global | 所有請求 |
| Service | 特定 Service 的所有 Route |
| Route | 特定 Route |
| Consumer | 特定 Consumer |

```bash
# 全域啟用 Rate Limiting
curl -X POST http://localhost:8765/plugins \
  -d name=rate-limiting \
  -d config.minute=100 \
  -d config.policy=local

# 在特定 Service 啟用 Key Auth
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=key-auth

# 在特定 Route 啟用 JWT
curl -X POST http://localhost:8765/routes/my-api-route/plugins \
  -d name=jwt

# 查看所有 Plugins
curl http://localhost:8765/plugins

# 刪除 Plugin
curl -X DELETE http://localhost:8765/plugins/{plugin-id}
```

詳見 [03-plugins.md](03-plugins.md)
