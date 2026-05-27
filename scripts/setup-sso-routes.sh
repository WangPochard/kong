#!/usr/bin/env bash
# =============================================================================
# Kong SSO Route Setup Script
# 針對 ~/sso-fhir 架構自動設置 Kong 路由、限流、CORS
#
# 使用方式：
#   chmod +x setup-sso-routes.sh
#   ./setup-sso-routes.sh              # 使用預設值
#   ./setup-sso-routes.sh --dry-run    # 只印指令，不執行
#   ./setup-sso-routes.sh --clean      # 清除所有 SSO 相關設定後重建
#
# 環境需求：
#   - Kong Admin API 可用（預設 localhost:8765）
#   - curl, jq 已安裝
# =============================================================================

set -euo pipefail

# ─── 設定區（可依環境修改）─────────────────────────────────────────────────
KONG_ADMIN="${KONG_ADMIN:-http://localhost:8765}"
SSO_UPSTREAM="${SSO_UPSTREAM:-http://sso-fhir:8000}"  # Kong 能連到的 SSO 內部 URL
VALKEY_HOST="${VALKEY_HOST:-cap-valkey}"
VALKEY_PORT="${VALKEY_PORT:-6379}"
VALKEY_DB="${VALKEY_DB:-2}"             # Kong 用 DB 2，避開 SSO(1) 和 CAP(0)
CORS_ORIGINS="${CORS_ORIGINS:-http://localhost:3000}"  # 逗號分隔多個 origin
ADMIN_ALLOWED_IPS="${ADMIN_ALLOWED_IPS:-172.25.0.0/16,127.0.0.1}"

# ─── 旗標 ──────────────────────────────────────────────────────────────────
DRY_RUN=false
CLEAN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --clean)   CLEAN=true ;;
    --help|-h)
      echo "用法: $0 [--dry-run] [--clean]"
      echo "  --dry-run  只印出 curl 指令，不實際執行"
      echo "  --clean    先清除所有 sso-* 設定再重建"
      exit 0
      ;;
  esac
done

# ─── 工具函數 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR ]${NC} $*"; }
section() { echo -e "\n${BLUE}══ $* ══${NC}"; }

api() {
  local method="$1"; shift
  local path="$1";   shift
  if [[ "$DRY_RUN" == true ]]; then
    echo "  [DRY] curl -s -X $method $KONG_ADMIN$path $*"
    return 0
  fi
  curl -s -X "$method" "$KONG_ADMIN$path" "$@"
}

api_post() {
  local path="$1"; shift
  api POST "$path" -H "Content-Type: application/json" -d "$@"
}

api_delete() {
  local path="$1"
  api DELETE "$path"
}

# 取得資源 ID（回傳 id 或 null）
get_id() {
  local path="$1"
  curl -s "$KONG_ADMIN$path" | jq -r '.id // empty' 2>/dev/null || echo ""
}

# ─── 前置確認 ────────────────────────────────────────────────────────────────
section "前置確認"

if [[ "$DRY_RUN" == true ]]; then
  warn "DRY RUN 模式，只顯示指令不執行"
fi

if ! command -v jq &>/dev/null; then
  if [[ "$DRY_RUN" == true ]]; then
    warn "jq 未安裝，dry-run 模式下繼續（實際執行前請先安裝）"
    warn "  Ubuntu/Debian: sudo apt install jq"
    warn "  macOS: brew install jq"
  else
    error "需要 jq，請先安裝："
    error "  Ubuntu/Debian: sudo apt install jq"
    error "  macOS: brew install jq"
    exit 1
  fi
fi

if [[ "$DRY_RUN" == false ]]; then
  KONG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$KONG_ADMIN/status" 2>/dev/null || echo "000")
  if [[ "$KONG_STATUS" != "200" ]]; then
    error "Kong Admin API 無法連線：$KONG_ADMIN (HTTP $KONG_STATUS)"
    error "請確認 Kong 已啟動：cd ~/kong && docker compose up -d"
    exit 1
  fi
  ok "Kong Admin API 可連線"
fi

# ─── 清除舊設定 ──────────────────────────────────────────────────────────────
if [[ "$CLEAN" == true ]] && [[ "$DRY_RUN" == false ]]; then
  section "清除舊設定（sso-* 開頭的資源）"

  # 刪 plugins（要先刪 plugin 才能刪 route/service）
  PLUGIN_IDS=$(curl -s "$KONG_ADMIN/plugins" | jq -r '.data[] | select(.service.name=="sso-fhir") | .id' 2>/dev/null || echo "")
  for id in $PLUGIN_IDS; do
    info "刪除 plugin: $id"
    api_delete "/plugins/$id" >/dev/null && ok "  deleted"
  done

  # 刪 routes（根據 service name）
  ROUTE_IDS=$(curl -s "$KONG_ADMIN/routes" | jq -r '.data[] | select(.name | startswith("sso-")) | .id' 2>/dev/null || echo "")
  for id in $ROUTE_IDS; do
    info "刪除 route: $id"
    api_delete "/routes/$id" >/dev/null && ok "  deleted"
  done

  # 刪 service
  SVC_ID=$(get_id "/services/sso-fhir")
  if [[ -n "$SVC_ID" ]]; then
    info "刪除 service: sso-fhir"
    api_delete "/services/sso-fhir" >/dev/null && ok "  deleted"
  fi

  ok "清除完成"
fi

# ─── 建立 Service ─────────────────────────────────────────────────────────────
section "建立 SSO Service"

SVC_RESULT=$(api_post "/services" "$(cat <<JSON
{
  "name": "sso-fhir",
  "url": "$SSO_UPSTREAM",
  "connect_timeout": 5000,
  "read_timeout": 60000,
  "write_timeout": 60000
}
JSON
)")

if echo "$SVC_RESULT" | jq -e '.id' >/dev/null 2>&1 || [[ "$DRY_RUN" == true ]]; then
  ok "Service 建立：sso-fhir → $SSO_UPSTREAM"
elif echo "$SVC_RESULT" | grep -q "already exists"; then
  warn "Service 已存在，繼續（使用 --clean 可重建）"
else
  error "建立 Service 失敗：$SVC_RESULT"
  exit 1
fi

# ─── 建立 Routes ─────────────────────────────────────────────────────────────
section "建立 Routes"

create_route() {
  local name="$1"
  local payload="$2"
  if [[ "$DRY_RUN" == true ]]; then
    api_post "/services/sso-fhir/routes" "$payload"
    ok "Route: $name"
    return 0
  fi
  local result
  result=$(api_post "/services/sso-fhir/routes" "$payload")

  if echo "$result" | jq -e '.id' >/dev/null 2>&1; then
    ok "Route: $name"
  elif echo "$result" | grep -q "already exists"; then
    warn "Route 已存在（跳過）: $name"
  else
    error "Route 建立失敗 ($name): $result"
  fi
}

# 登入（單獨一條，方便精確限流）
create_route "sso-auth-login" "$(cat <<JSON
{
  "name": "sso-auth-login",
  "paths": ["/api/sso/auth/login"],
  "methods": ["POST", "OPTIONS"],
  "strip_path": false,
  "preserve_host": false
}
JSON
)"

# Refresh token
create_route "sso-auth-refresh" "$(cat <<JSON
{
  "name": "sso-auth-refresh",
  "paths": ["/api/sso/auth/refresh"],
  "methods": ["POST", "OPTIONS"],
  "strip_path": false
}
JSON
)"

# Logout
create_route "sso-auth-logout" "$(cat <<JSON
{
  "name": "sso-auth-logout",
  "paths": ["/api/sso/auth/logout"],
  "methods": ["POST", "OPTIONS"],
  "strip_path": false
}
JSON
)"

# 其餘 auth（激活、忘記密碼）
create_route "sso-auth-misc" "$(cat <<JSON
{
  "name": "sso-auth-misc",
  "paths": ["/api/sso/auth"],
  "methods": ["GET", "POST", "OPTIONS"],
  "strip_path": false
}
JSON
)"

# 個人資料
create_route "sso-users-me" "$(cat <<JSON
{
  "name": "sso-users-me",
  "paths": ["/api/sso/users"],
  "methods": ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
  "strip_path": false
}
JSON
)"

# Admin（有 IP 限制）
create_route "sso-admin" "$(cat <<JSON
{
  "name": "sso-admin",
  "paths": ["/api/sso/admin"],
  "methods": ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
  "strip_path": false
}
JSON
)"

# 查詢 / lookup
create_route "sso-lookup" "$(cat <<JSON
{
  "name": "sso-lookup",
  "paths": ["/api/sso/lookup"],
  "methods": ["GET", "OPTIONS"],
  "strip_path": false
}
JSON
)"

# 子系統（entry-code 會回傳 302，Kong 預設穿透）
create_route "sso-systems" "$(cat <<JSON
{
  "name": "sso-systems",
  "paths": ["/api/sso/systems"],
  "methods": ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
  "strip_path": false
}
JSON
)"

# Health check
create_route "sso-health" "$(cat <<JSON
{
  "name": "sso-health",
  "paths": ["/api/sso/health", "/api/sso"],
  "methods": ["GET"],
  "strip_path": false
}
JSON
)"

# ─── 取得 Route ID（後續掛 Plugin 用）────────────────────────────────────────
get_route_id() {
  local name="$1"
  curl -s "$KONG_ADMIN/routes/$name" | jq -r '.id // empty' 2>/dev/null || echo ""
}

# ─── Plugins ─────────────────────────────────────────────────────────────────
section "設定 Plugins"

add_plugin_to_route() {
  local route_name="$1"
  local payload="$2"
  # 用 grep 取 name，不依賴 jq
  local plugin_name
  plugin_name=$(echo "$payload" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
  if [[ "$DRY_RUN" == true ]]; then
    api_post "/routes/$route_name/plugins" "$payload"
    ok "Plugin $plugin_name → $route_name"
    return 0
  fi
  local result
  result=$(api_post "/routes/$route_name/plugins" "$payload")

  if echo "$result" | grep -q '"id"'; then
    ok "Plugin $plugin_name → $route_name"
  elif echo "$result" | grep -q "already exists"; then
    warn "Plugin 已存在（跳過）: $plugin_name on $route_name"
  else
    error "Plugin 設定失敗 ($plugin_name on $route_name): $result"
  fi
}

add_global_plugin() {
  local payload="$1"
  local plugin_name
  plugin_name=$(echo "$payload" | grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*: *"\(.*\)"/\1/')
  if [[ "$DRY_RUN" == true ]]; then
    api_post "/plugins" "$payload"
    ok "Global Plugin: $plugin_name"
    return 0
  fi
  local result
  result=$(api_post "/plugins" "$payload")

  if echo "$result" | grep -q '"id"'; then
    ok "Global Plugin: $plugin_name"
  elif echo "$result" | grep -q "already exists"; then
    warn "Global Plugin 已存在（跳過）: $plugin_name"
  else
    error "Global Plugin 設定失敗 ($plugin_name): $result"
  fi
}

# 登入限流（最嚴）
add_plugin_to_route "sso-auth-login" "$(cat <<JSON
{
  "name": "rate-limiting",
  "config": {
    "minute": 20,
    "hour": 200,
    "policy": "redis",
    "redis": {
      "host": "$VALKEY_HOST",
      "port": $VALKEY_PORT,
      "database": $VALKEY_DB
    },
    "fault_tolerant": true,
    "hide_client_headers": false
  }
}
JSON
)"

# Refresh 限流
add_plugin_to_route "sso-auth-refresh" "$(cat <<JSON
{
  "name": "rate-limiting",
  "config": {
    "minute": 60,
    "hour": 500,
    "policy": "redis",
    "redis": {
      "host": "$VALKEY_HOST",
      "port": $VALKEY_PORT,
      "database": $VALKEY_DB
    },
    "fault_tolerant": true
  }
}
JSON
)"

# 激活/忘記密碼限流（防濫用）
add_plugin_to_route "sso-auth-misc" "$(cat <<JSON
{
  "name": "rate-limiting",
  "config": {
    "minute": 10,
    "hour": 50,
    "policy": "redis",
    "redis": {
      "host": "$VALKEY_HOST",
      "port": $VALKEY_PORT,
      "database": $VALKEY_DB
    },
    "fault_tolerant": true
  }
}
JSON
)"

# Admin IP 限制
IFS=',' read -ra IP_LIST <<< "$ADMIN_ALLOWED_IPS"
IP_JSON=$(printf '"%s",' "${IP_LIST[@]}" | sed 's/,$//')
add_plugin_to_route "sso-admin" "$(cat <<JSON
{
  "name": "ip-restriction",
  "config": {
    "allow": [$IP_JSON]
  }
}
JSON
)"

# 全域 CORS
IFS=',' read -ra ORIGIN_LIST <<< "$CORS_ORIGINS"
ORIGIN_JSON=$(printf '"%s",' "${ORIGIN_LIST[@]}" | sed 's/,$//')
add_global_plugin "$(cat <<JSON
{
  "name": "cors",
  "config": {
    "origins": [$ORIGIN_JSON],
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    "headers": [
      "Authorization",
      "Content-Type",
      "X-System-Ticket",
      "X-Exchange-Token",
      "X-Requested-With"
    ],
    "credentials": true,
    "max_age": 3600,
    "preflight_continue": false
  }
}
JSON
)"

# ─── 驗證 ────────────────────────────────────────────────────────────────────
section "驗證結果"

if [[ "$DRY_RUN" == false ]]; then
  echo ""
  info "已建立的 Routes："
  if command -v jq &>/dev/null; then
    curl -s "$KONG_ADMIN/routes" | jq -r '.data[] | select(.name | startswith("sso-")) | "  - \(.name): \(.paths[])"' 2>/dev/null || warn "無法列出 routes"
    echo ""
    info "已建立的 Plugins："
    curl -s "$KONG_ADMIN/plugins" | jq -r '.data[] | "  - \(.name) (route: \(.route.id // "global"))"' 2>/dev/null || warn "無法列出 plugins"
  else
    curl -s "$KONG_ADMIN/routes" | grep -o '"name":"[^"]*"' | grep sso || warn "無法列出 routes"
  fi
fi

# ─── 測試指令提示 ─────────────────────────────────────────────────────────────
section "快速測試指令"

cat <<'TIPS'
# 1. SSO Health（走 Kong）
curl -s http://localhost:8000/api/sso/health | jq .status

# 2. 登入取得 token
TOKEN=$(curl -s -X POST http://localhost:8000/api/sso/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"YOUR_USER","password":"YOUR_PASS"}' \
  | jq -r '.data[0].access_token // .data.access_token')
echo "Token: ${TOKEN:0:50}..."

# 3. 測試 entry-code（不要跟 redirect）
curl -v -X POST \
  "http://localhost:8000/api/sso/systems/YOUR_SYSTEM_ID/entry-code" \
  -H "Authorization: Bearer $TOKEN" \
  2>&1 | grep -E "< HTTP|Location:"
# 期望：302 + Location: http://subsystem.com?code=xxx

# 4. 確認限流 header
curl -I -X POST http://localhost:8000/api/sso/auth/login \
  -H "Content-Type: application/json" \
  -d '{}' 2>/dev/null | grep -i "RateLimit"

# 5. 查 Kong 路由狀態
curl -s http://localhost:8765/routes | jq '.data[] | select(.name|startswith("sso-")) | {name,paths}'
TIPS

echo ""
ok "設定完成！"
