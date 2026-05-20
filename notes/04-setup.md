# Kong 設置與操作

## 本地環境

設定檔位置：`/home/yisheng/kong/docker-compose.yml`

```bash
# 啟動
cd /home/yisheng/kong
docker compose up -d

# 關閉
docker compose down

# 查看 logs
docker compose logs -f kong
docker compose logs -f kong-db

# 重新跑 migrations（通常不需要，除非更新版本）
docker compose run --rm kong-migrations kong migrations up
```

**注意**：`kong-migrations` 服務設為 `restart: on-failure`，初次啟動成功後就停了，正常。

---

## 完整重置

```bash
cd /home/yisheng/kong

# 停止並移除所有容器和 volume（完全清空）
docker compose down -v

# 重新啟動（會自動跑 migrations bootstrap）
docker compose up -d
```

---

## 驗證設定正確

```bash
# 1. Kong proxy 正常
curl -I http://localhost:8000

# 2. Admin API 正常
curl http://localhost:8765/ | jq .version

# 3. Kong Manager（瀏覽器）
# http://localhost:8002
```

---

## 設定 Kong 代理本地 sso-fhir

常見情境：將 Kong 當作 sso-fhir 的 API Gateway 前端。

```bash
# sso-fhir 跑在 host 的 8001 port
# 在 Docker 網路中，host machine = host.docker.internal

# 建立 Service
curl -X POST http://localhost:8765/services \
  -d name=sso-fhir \
  -d url=http://host.docker.internal:8001

# 建立 Route（path-based）
curl -X POST http://localhost:8765/services/sso-fhir/routes \
  -d name=sso-fhir-route \
  -d "paths[]=/sso" \
  -d strip_path=true

# 測試
curl http://localhost:8000/sso/docs
```

---

## Declarative Config（deck）

deck 讓設定檔版本化，比 curl 逐一操作更好維護。

### 安裝 deck

```bash
# Linux
curl -sL https://github.com/Kong/deck/releases/latest/download/deck_linux_amd64.tar.gz | tar xz
sudo mv deck /usr/local/bin/

# 驗證
deck version
```

### 使用方式

```bash
# 匯出目前 Kong 設定到 YAML
deck gateway dump --kong-addr http://localhost:8765 -o kong.yaml

# 套用設定（sync = 讓 Kong 狀態和 YAML 一致）
deck gateway sync --kong-addr http://localhost:8765 kong.yaml

# 預覽差異（不實際套用）
deck gateway diff --kong-addr http://localhost:8765 kong.yaml

# 驗證 YAML 格式正確
deck file validate kong.yaml
```

### kong.yaml 範例

```yaml
_format_version: "3.0"
_transform: true

services:
  - name: my-api
    url: http://backend:8000
    routes:
      - name: my-api-route
        paths:
          - /v1/my-api
        strip_path: true
    plugins:
      - name: key-auth
        config:
          hide_credentials: true
      - name: rate-limiting
        config:
          minute: 100
          policy: local

consumers:
  - username: alice
    keyauth_credentials:
      - key: alice-secret-key

plugins:
  - name: cors
    config:
      origins:
        - "*"
      methods:
        - GET
        - POST
        - OPTIONS
      headers:
        - Authorization
        - Content-Type
      credentials: true
```

---

## 升級 Kong 版本

```bash
# 修改 docker-compose.yml 中的 image 版本
# 例如：kong:3.7.0 → kong:3.8.0

# 先跑 migration up（不是 bootstrap）
docker compose run --rm -e KONG_ADMIN_LISTEN= kong kong migrations up

# 重啟 Kong
docker compose up -d kong
```
