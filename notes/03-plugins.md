# Kong Plugins 參考

## 認證類

### Key Authentication（API Key）

最簡單的認證方式，Client 在 Header 或 Query String 帶 API Key。

```bash
# 1. 在 Service 啟用 key-auth
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=key-auth \
  -d config.key_names[]=apikey   # 預設：apikey
  # config.hide_credentials=true  # 轉發前移除 key（建議）

# 2. 建立 Consumer
curl -X POST http://localhost:8765/consumers \
  -d username=alice

# 3. 給 Consumer 一把 Key
curl -X POST http://localhost:8765/consumers/alice/key-auth \
  -d key=my-secret-key-123

# 呼叫方式
curl http://localhost:8000/v1/my-api \
  -H "apikey: my-secret-key-123"
# 或 query string：
# curl "http://localhost:8000/v1/my-api?apikey=my-secret-key-123"
```

---

### JWT Authentication

適合已有 Keycloak / Auth Server 的場景。

```bash
# 1. 在 Route 啟用 jwt
curl -X POST http://localhost:8765/routes/my-api-route/plugins \
  -d name=jwt \
  -d config.claims_to_verify[]=exp  # 驗證過期時間

# 2. 建立 Consumer
curl -X POST http://localhost:8765/consumers \
  -d username=alice

# 3. 建立 JWT 憑證（Kong 管理的 key pair）
curl -X POST http://localhost:8765/consumers/alice/jwt
# 回傳 key（iss）和 secret，用這個產生 JWT

# 呼叫方式
curl http://localhost:8000/v1/my-api \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

**與 Keycloak 整合（驗證外部 JWT）：**

使用 `jwt` plugin 或更完整的 `openid-connect` plugin（Kong Enterprise）。

免費方案：用 `pre-function` plugin 自訂驗證邏輯，或改用 `hmac-auth`。

---

### Basic Authentication

```bash
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=basic-auth \
  -d config.hide_credentials=true

# 建立 Consumer 的帳密
curl -X POST http://localhost:8765/consumers/alice/basic-auth \
  -d username=alice \
  -d password=secret

# 呼叫
curl http://localhost:8000/v1/my-api \
  -u alice:secret
```

---

## 流量控制

### Rate Limiting

```bash
# 全域限流
curl -X POST http://localhost:8765/plugins \
  -d name=rate-limiting \
  -d config.minute=60 \
  -d config.hour=1000 \
  -d config.policy=local   # local / redis / cluster

# Per-consumer 限流（先掛全域，再針對特定 consumer 覆蓋）
curl -X POST http://localhost:8765/consumers/alice/plugins \
  -d name=rate-limiting \
  -d config.minute=200

# Redis 模式（多節點共享計數）
curl -X POST http://localhost:8765/plugins \
  -d name=rate-limiting \
  -d config.minute=100 \
  -d config.policy=redis \
  -d config.redis.host=redis-host \
  -d config.redis.port=6379
```

**回應 Header：**
- `X-RateLimit-Limit-Minute`
- `X-RateLimit-Remaining-Minute`
- 超過限制回傳 `429 Too Many Requests`

---

### Request Size Limiting

```bash
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=request-size-limiting \
  -d config.allowed_payload_size=10   # MB
```

---

## 轉換類

### Request Transformer

修改轉發到 upstream 之前的請求。

```bash
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=request-transformer \
  -d "config.add.headers[]=X-Custom-Header:value" \
  -d "config.remove.headers[]=Authorization" \
  -d "config.replace.headers[]=Host:internal-host" \
  -d "config.add.querystring[]=source:kong"
```

### Response Transformer

修改回傳給 client 之前的回應。

```bash
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=response-transformer \
  -d "config.add.headers[]=X-Powered-By:Kong" \
  -d "config.remove.headers[]=Server"
```

---

## 監控/日誌

### HTTP Log

```bash
curl -X POST http://localhost:8765/plugins \
  -d name=http-log \
  -d config.http_endpoint=http://log-server:9000/kong-logs \
  -d config.method=POST \
  -d config.timeout=1000 \
  -d config.keepalive=1000
```

### File Log

```bash
curl -X POST http://localhost:8765/plugins \
  -d name=file-log \
  -d config.path=/tmp/kong.log \
  -d config.reopen=false
```

### Prometheus

```bash
curl -X POST http://localhost:8765/plugins \
  -d name=prometheus

# Metrics 端點
curl http://localhost:8765/metrics
```

---

## CORS

```bash
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=cors \
  -d "config.origins[]=*" \
  -d "config.methods[]=GET" \
  -d "config.methods[]=POST" \
  -d "config.methods[]=OPTIONS" \
  -d "config.headers[]=Authorization" \
  -d "config.headers[]=Content-Type" \
  -d config.credentials=true \
  -d config.max_age=3600 \
  -d config.preflight_continue=false
```

---

## IP Restriction

```bash
# 只允許特定 IP
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=ip-restriction \
  -d "config.allow[]=192.168.1.0/24" \
  -d "config.allow[]=10.0.0.1"

# 封鎖特定 IP
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=ip-restriction \
  -d "config.deny[]=1.2.3.4"
```

---

## ACL（搭配認證使用）

```bash
# 啟用 ACL plugin
curl -X POST http://localhost:8765/services/my-api/plugins \
  -d name=acl \
  -d "config.allow[]=admin-group" \
  -d "config.allow[]=developer-group"

# 將 Consumer 加入 Group
curl -X POST http://localhost:8765/consumers/alice/acls \
  -d group=admin-group
```
