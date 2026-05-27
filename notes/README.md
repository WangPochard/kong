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

## 新增筆記原則

- **每個主題一個文件**，不要混在一起
- 有實際測試過的指令才加入，加上預期結果
- 踩到的坑記錄在 `05-troubleshooting.md`
- 新設定的 Service/Plugin 組合記錄在 `06-recipes.md`（有需要再建）
