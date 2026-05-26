# Kong 疑難排解

## 常見問題

### Kong Manager 顯示 "Plugins could not be retrieved"

**現象**：進入 Kong Manager (`http://localhost:8002`) 後，Plugins 頁面顯示：
> Plugins could not be retrieved. Data cannot be displayed due to an error.

**原因**：Kong Manager UI 跑在瀏覽器裡，需要知道 Admin API 的位置。若 Admin API **不在預設的 8001 port**（例如本環境用 8765），而 `KONG_ADMIN_GUI_API_URL` 又沒設定，UI 就會打 `:8001` 打不到而報錯。

**修復**：在 `docker-compose.yml` 加上：

```yaml
environment:
  KONG_ADMIN_GUI_URL: http://${WSL_IP}:8002       # Kong Manager 自己的 URL
  KONG_ADMIN_GUI_API_URL: http://${WSL_IP}:8765   # ← 這個必加！指向 Admin API
```

`WSL_IP` 定義在 `.env`：

```env
WSL_IP=172.27.207.106   # 執行 hostname -I | awk '{print $1}' 取得
```

然後重啟：

```bash
docker compose up -d --force-recreate kong
```

> **⚠️ WSL2 IP 注意事項：**
> - 從 Windows 瀏覽器存取時，必須用 WSL2 IP（不能用 localhost）
> - WSL2 IP **每次重開機都會變**，需更新 `.env` 的 `WSL_IP` 後重啟 Kong
> - 更新流程：`hostname -I | awk '{print $1}'` → 改 `.env` → `docker compose up -d --force-recreate kong`

> **兩個變數的差別：**
> - `KONG_ADMIN_GUI_URL` → Kong Manager 本身的 URL（決定 CORS 允許的 Origin）
> - `KONG_ADMIN_GUI_API_URL` → Kong Manager 要呼叫的 Admin API URL（讓瀏覽器知道 API 在哪）

---

### Kong 啟動失敗

**現象**：`docker compose up` 後 kong 容器一直 restarting

```bash
# 看詳細 log
docker compose logs kong

# 常見原因 1：DB 還沒 ready，migrations 還在跑
# → 等 kong-migrations 完成後 kong 才會成功啟動
docker compose logs kong-migrations

# 常見原因 2：migrations 還沒跑過（bootstrap）
# → docker-compose.yml 中的 depends_on condition: service_completed_successfully 應該會處理
# → 手動跑：
docker compose run --rm kong-migrations kong migrations bootstrap
```

### 502 Bad Gateway

Kong 收到請求但 upstream 沒回應。

```bash
# 確認 upstream target 是否正確
curl http://localhost:8765/services/my-api | jq '{host,port,path,protocol}'

# 測試 Kong 容器能否連到 upstream
docker exec -it kong-kong-1 curl http://<upstream-host>:<port>/health

# WSL 環境中，要連到 host machine 用 host.docker.internal
docker exec -it kong-kong-1 curl http://host.docker.internal:8001/docs
```

### 404 No route matched

請求到 proxy port 但 Kong 找不到匹配的 Route。

```bash
# 確認 Route 設定
curl http://localhost:8765/routes | jq '.data[] | {name, paths, hosts, methods}'

# 確認 Route 有掛到正確 Service
curl http://localhost:8765/routes/my-api-route | jq '{service, paths, strip_path}'

# 測試 path 是否正確
curl -v http://localhost:8000/v1/my-api
# 看 response header: X-Kong-Matched-Route
```

### 401 Unauthorized（認證失敗）

```bash
# 確認 plugin 有掛在正確層級
curl http://localhost:8765/services/my-api/plugins | jq '.data[].name'
curl http://localhost:8765/routes/my-api-route/plugins | jq '.data[].name'

# Key Auth：確認 Consumer 的 key
curl http://localhost:8765/consumers/alice/key-auth | jq '.'

# JWT：確認 Consumer 的 credentials
curl http://localhost:8765/consumers/alice/jwt | jq '.'
```

### 429 Too Many Requests

```bash
# 查看限流設定
curl http://localhost:8765/plugins | jq '.data[] | select(.name=="rate-limiting")'

# 查看 response headers 了解限流狀態
curl -v http://localhost:8000/v1/my-api 2>&1 | grep -i ratelimit
```

---

## 診斷工具

```bash
# Kong 整體健康狀態
curl http://localhost:8765/health

# 看 Kong 版本和已載入 plugins
curl http://localhost:8765/ | jq '{version, lua_version}'
curl http://localhost:8765/plugins/enabled | jq '.enabled_plugins'

# 追蹤一個請求
curl -v http://localhost:8000/v1/my-api 2>&1
# 注意 response headers：
# X-Kong-Upstream-Latency  — upstream 處理時間
# X-Kong-Proxy-Latency     — Kong 自身處理時間
# X-Kong-Matched-Route     — 匹配到的 Route

# 進入 Kong 容器排查
docker exec -it kong-kong-1 /bin/sh

# 在容器內測試 upstream 連線
docker exec -it kong-kong-1 curl http://host.docker.internal:8001/
```

---

## 效能調整

```bash
# 查看 Kong worker 數量（影響並發）
docker exec -it kong-kong-1 kong config get worker_processes

# 調整方式：在 docker-compose.yml 加環境變數
# KONG_NGINX_WORKER_PROCESSES: auto
```

---

## Log 位置

在 docker-compose.yml 設定中，logs 輸出到 stdout/stderr：
```
KONG_PROXY_ACCESS_LOG: /dev/stdout
KONG_PROXY_ERROR_LOG: /dev/stderr
KONG_ADMIN_ACCESS_LOG: /dev/stdout
KONG_ADMIN_ERROR_LOG: /dev/stderr
```

所以用 `docker compose logs kong` 可以看到所有 access log 和 error log。
