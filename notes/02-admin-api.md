# Kong Admin API 速查

Admin API 端點：`http://localhost:8765`

---

## 基本查詢

```bash
# Kong 狀態
curl http://localhost:8765/

# 節點資訊（版本、plugins 清單）
curl http://localhost:8765/

# 所有已啟用的 Plugins 類型
curl http://localhost:8765/plugins/enabled
```

---

## CRUD 速查表

### Services
```bash
GET    /services              # 列出所有
POST   /services              # 建立
GET    /services/{name|id}    # 查詢
PATCH  /services/{name|id}    # 更新（部分欄位）
PUT    /services/{name|id}    # 建立或替換
DELETE /services/{name|id}    # 刪除
```

### Routes
```bash
GET    /routes                        # 列出所有
POST   /services/{service}/routes     # 建立（掛在 service 下）
POST   /routes                        # 建立（指定 service 欄位）
GET    /routes/{name|id}              # 查詢
PATCH  /routes/{name|id}              # 更新
DELETE /routes/{name|id}              # 刪除
```

### Upstreams & Targets
```bash
GET    /upstreams                                    # 列出所有
POST   /upstreams                                    # 建立
GET    /upstreams/{name|id}/targets                  # 列出 targets
POST   /upstreams/{name|id}/targets                  # 加入 target
DELETE /upstreams/{name|id}/targets/{target|id}      # 移除 target
GET    /upstreams/{name|id}/health                   # 健康檢查狀態
```

### Consumers
```bash
GET    /consumers                      # 列出所有
POST   /consumers                      # 建立
GET    /consumers/{username|id}        # 查詢
DELETE /consumers/{username|id}        # 刪除

# 認證憑證
GET    /consumers/{consumer}/key-auth  # 列出 API Keys
POST   /consumers/{consumer}/key-auth  # 建立 API Key
DELETE /consumers/{consumer}/key-auth/{id}

GET    /consumers/{consumer}/jwt       # 列出 JWT 憑證
POST   /consumers/{consumer}/jwt       # 建立 JWT 憑證
```

### Plugins
```bash
GET    /plugins                           # 列出所有 (global)
POST   /plugins                           # 建立 global plugin
POST   /services/{service}/plugins        # 掛在 service
POST   /routes/{route}/plugins            # 掛在 route
POST   /consumers/{consumer}/plugins      # 掛在 consumer
PATCH  /plugins/{id}                      # 更新
DELETE /plugins/{id}                      # 刪除
```

---

## 常用過濾查詢

```bash
# 查某個 Service 的所有 Routes
curl http://localhost:8765/services/my-api/routes

# 查某個 Route 的所有 Plugins
curl http://localhost:8765/routes/my-api-route/plugins

# 查某個 Consumer 的所有 Plugins
curl http://localhost:8765/consumers/alice/plugins

# 分頁（size 最大 1000）
curl "http://localhost:8765/services?size=10&offset=<next_offset>"
```

---

## 常用 curl 技巧

```bash
# JSON 格式輸出（需 jq）
curl http://localhost:8765/services | jq

# 用 -s 靜音（不顯示進度）
curl -s http://localhost:8765/services | jq '.data[].name'

# PATCH 更新（只送要改的欄位）
curl -X PATCH http://localhost:8765/services/my-api \
  -H "Content-Type: application/json" \
  -d '{"read_timeout": 30000}'

# 陣列欄位（form-data 格式）
curl -X POST http://localhost:8765/routes \
  -d "paths[]=/v1" \
  -d "methods[]=GET" \
  -d "methods[]=POST" \
  -d "service.name=my-api"

# 陣列欄位（JSON 格式）
curl -X POST http://localhost:8765/routes \
  -H "Content-Type: application/json" \
  -d '{"paths":["/v1"],"methods":["GET","POST"],"service":{"name":"my-api"}}'
```

---

## Declarative Config（deck）

比 curl 逐一操作更好維護的方式：

```bash
# 安裝 deck（Kong 官方 CLI）
# https://docs.konghq.com/deck/

# 匯出目前設定
deck gateway dump > kong.yaml

# 套用設定檔
deck gateway sync kong.yaml

# diff 檢視差異
deck gateway diff kong.yaml
```

詳見 [04-setup.md](04-setup.md)
