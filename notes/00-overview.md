# Kong 概覽

## 這個 Kong 環境

- **版本**: Kong 3.7.0
- **模式**: DB-backed (PostgreSQL 16)
- **部署**: Docker Compose

### 端口配置

| 端口 | 用途 |
|------|------|
| `8000` | HTTP Proxy（流量入口） |
| `8443` | HTTPS Proxy |
| `8765` | Admin API |
| `8002` | Kong Manager (Admin GUI) |
| `5433` | PostgreSQL（host 端，容器內為 5432）|

### 快速驗證

```bash
# 確認 Kong 運行
curl http://localhost:8765/

# 看所有 Services
curl http://localhost:8765/services

# 看所有 Routes
curl http://localhost:8765/routes
```

---

## Kong 是什麼

Kong 是一個 API Gateway，夾在 Client 和 Backend Service 之間，負責：
- **路由**：依照 Host / Path / Header 將請求轉發到對應的 upstream service
- **認證**：JWT / API Key / OAuth2 / Basic Auth
- **限流**：Rate Limiting
- **監控**：Logging、Metrics

```
Client → Kong Proxy (8000) → Upstream Service
              ↑
         Kong Plugins（認證、限流、轉換...）
```

---

## 核心物件關係

```
Service  ──1:N──  Route
   │
   └── Upstream ──1:N── Target（實際 server）

Consumer ──M:N── Plugin（per-consumer 設定）
Plugin 可掛在 Global / Service / Route / Consumer 任一層
```

詳見 [01-core-concepts.md](01-core-concepts.md)
