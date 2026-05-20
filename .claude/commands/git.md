# Kong 專案 Git 助手

協助處理 Kong 專案的 git 相關工作，包含：
- 產出 commit message
- 撰寫 `.gitignore`
- 產生 GitHub Actions CI/CD 腳本

**絕對禁止**：不能執行任何 git add、git commit、git push 或任何會修改 git 狀態的指令。只能讀取資訊。

---

## 判斷使用者意圖

根據使用者的訊息，選擇對應的模式：

| 關鍵字 / 情境 | 執行模式 |
|---|---|
| 「commit」、「提交」、「訊息」、無特別說明 | → [Commit Message 模式] |
| 「gitignore」、「忽略」、「ignore」 | → [.gitignore 模式] |
| 「ci」、「cd」、「pipeline」、「github actions」、「workflow」 | → [CI/CD 模式] |
| 「初始化」、「init」、「還沒有 git」 | → 引導初始化，輸出 .gitignore 後停止 |

若使用者沒有明確說明，執行 **Commit Message 模式**。

---

## [Commit Message 模式]

### Step 1：確認 git 狀態

```bash
git -C /home/yisheng/kong status 2>&1
```

若回傳 `fatal: not a git repository`，切換到 **[引導初始化]** 流程後停止。

### Step 2：判斷是否為初始 commit

```bash
git -C /home/yisheng/kong log --oneline -1 2>/dev/null || echo "NO_COMMITS"
```

### Step 3：取得變更內容

```bash
git -C /home/yisheng/kong status
git -C /home/yisheng/kong diff HEAD
git -C /home/yisheng/kong diff --cached
```

### Step 4：分析並輸出建議

**Kong 專案的 commit type：**

| type | 適用情境 |
|------|---------|
| `Initial Commit` | 第一筆 commit |
| `feat` | 新增 Service / Route / Plugin 設定 |
| `fix` | 修正錯誤的設定（端口、路徑、timeout 等） |
| `config` | 調整 docker-compose.yml 或環境設定 |
| `docs` | 更新 `notes/` 知識庫文件 |
| `ci` | 新增或修改 GitHub Actions workflow |
| `chore` | .gitignore、skill 指令等維護性工作 |
| `refactor` | 重組設定結構，不改行為 |

**格式：**
```
<type>: <一句話摘要（中文，動詞開頭，≤50字）>

1. <檔案/設定項>：<做了什麼，與原本的差異>
2. <檔案/設定項>：<做了什麼，與原本的差異>
```

**拆分原則：** 若同時包含設定變更 + 知識庫文件、或多個不相關 Service/Plugin、或 CI 腳本 + 功能變更，建議拆分 commit。

**輸出格式：**
```
建議分成 N 個 commit：

【Commit 1】git add <檔案>
<message>

【Commit 2】git add <檔案>
<message>
```

若不需拆分，直接輸出單一 commit message + `git add <建議清單>`。

---

## [.gitignore 模式]

讀取目前目錄結構：
```bash
ls /home/yisheng/kong/
ls /home/yisheng/kong/.github/ 2>/dev/null || echo "no .github"
```

根據實際檔案輸出 `.gitignore`，適用於 Kong 專案：

```gitignore
# 環境設定（含密碼，絕對不能進 git）
.env
*.env
.env.*

# Kong PostgreSQL volume（由 Docker 管理，不需版控）
kong-db-data/

# deck 操作暫存
*.bak

# 編輯器
.vscode/
.idea/
*.swp
*~

# OS
.DS_Store
Thumbs.db
```

直接用 Write 工具寫入 `/home/yisheng/kong/.gitignore`（若已存在先讀取再決定是否覆蓋或合併）。

寫入後輸出：
```
已寫入 .gitignore。

注意：docker-compose.yml 含有資料庫密碼，建議改用環境變數：
  - 將敏感值移到 .env
  - docker-compose.yml 改用 ${VARIABLE} 引用
  - .env.example 提供範本並進 git
```

---

## [CI/CD 模式]

### Step 1：了解需求

詢問使用者（若訊息未說明）：
1. **觸發時機**：push to main？PR？手動觸發？
2. **要做什麼**：驗證 docker-compose 格式？自動部署？lint kong config？

若使用者沒有說明，預設產生：**「驗證 Kong 設定格式」+ 「可選的自動部署」**。

### Step 2：確認目錄結構

```bash
ls /home/yisheng/kong/
ls /home/yisheng/kong/.github/workflows/ 2>/dev/null || echo "no workflows"
```

### Step 3：產生 GitHub Actions workflow

依需求選擇對應模板輸出，並用 Write 工具寫入 `.github/workflows/` 目錄。

---

#### 模板 A：驗證 Kong 設定（推薦，最輕量）

**適用：** 每次 push / PR 時確保 docker-compose.yml 格式正確、notes 文件存在。

```yaml
# .github/workflows/validate.yml
name: Validate Kong Config

on:
  push:
    branches: [main, master]
  pull_request:
    branches: [main, master]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Validate docker-compose syntax
        run: docker compose -f docker-compose.yml config --quiet

      - name: Check required notes files
        run: |
          required=(
            "notes/00-overview.md"
            "notes/01-core-concepts.md"
            "notes/02-admin-api.md"
            "notes/03-plugins.md"
            "notes/04-setup.md"
            "notes/05-troubleshooting.md"
          )
          for f in "${required[@]}"; do
            [ -f "$f" ] || { echo "Missing: $f"; exit 1; }
          done
          echo "All required notes files present."
```

---

#### 模板 B：驗證 + deck lint（若使用 declarative config）

**適用：** 有 `kong.yaml` 宣告式設定檔時，用 deck 驗證格式。

```yaml
# .github/workflows/validate.yml
name: Validate Kong Config

on:
  push:
    branches: [main, master]
  pull_request:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Validate docker-compose syntax
        run: docker compose -f docker-compose.yml config --quiet

      - name: Install deck
        run: |
          curl -sL https://github.com/Kong/deck/releases/latest/download/deck_linux_amd64.tar.gz \
            | tar xz -C /usr/local/bin deck

      - name: Lint Kong declarative config
        run: deck file validate kong.yaml
```

---

#### 模板 C：自動部署到遠端主機（SSH）

**適用：** push to main 時自動 SSH 進伺服器執行 `docker compose pull && up`。

```yaml
# .github/workflows/deploy.yml
name: Deploy Kong

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy via SSH
        uses: appleboy/ssh-action@v1
        with:
          host: ${{ secrets.DEPLOY_HOST }}
          username: ${{ secrets.DEPLOY_USER }}
          key: ${{ secrets.DEPLOY_SSH_KEY }}
          script: |
            cd /home/yisheng/kong
            git pull origin main
            docker compose pull
            docker compose up -d
            docker compose ps
```

**需在 GitHub repo → Settings → Secrets 加入：**
- `DEPLOY_HOST`：伺服器 IP 或 domain
- `DEPLOY_USER`：SSH 使用者名稱
- `DEPLOY_SSH_KEY`：SSH 私鑰內容

---

### Step 4：輸出說明

寫入檔案後告知：
```
已寫入 .github/workflows/<filename>.yml

下一步：
1. git add .github/
2. git commit -m "ci: 新增 GitHub Actions <說明>"
3. git push

推送後到 GitHub repo → Actions 頁面確認 workflow 運行狀態。
```

---

## [引導初始化]

```
此專案尚未初始化 git。請先執行：

  cd /home/yisheng/kong
  git init

建議同時執行 /commit gitignore 讓我幫你產 .gitignore。
```

---

## 輸出原則

- Commit Message 模式：只輸出訊息與 git add 建議，不執行 git 操作，不加前言
- .gitignore / CI/CD 模式：直接寫入檔案，然後簡短說明下一步
