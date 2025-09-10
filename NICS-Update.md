# 📌 NICS-Update.ps1 (修正版 2025-09-10.120)

`NICS-Update.ps1` 是一個自動化 PowerShell 腳本，專為 **Windows Server + DNS Server** 環境設計，用於自動下載 NICS 黑名單並更新 DNS Policy，同時支援多種格式轉換、NAS 備份與多管道通知。

---

## 🚀 功能
- 從 NICS 平台下載最新黑名單，支援 Proxy 與 NAS 備份還原。
- 自動比對 SHA256，僅在黑名單更新時才進行覆蓋。
- 清除舊的 `NICS-*` DNS Policy，並建立新的 Policy。
- 將黑名單轉換為 **AdGuard** 與 **Pi-hole** 格式。
- 備份黑名單及轉換檔至 NAS。
- 上傳 GitHub Gist (僅 AdGuard.txt / Pi-hole.txt)，自動偵測是否更新。
- 自動清理舊日誌 (保留最近 7 天)。
- 多管道通知：
  - 📧 Email
  - 📝 Windows Event Log
  - 📲 LINE Notify
  - 💬 Slack / Teams Webhook

---

## ⚙️ 參數說明
| 參數 | 必要 | 說明 |
|------|------|------|
| `DST` | ✅ | 本地黑名單檔案路徑 (e.g., `C:\dns\NICS-Policy.txt`) |
| `Token` | ✅ | NICS API Token |
| `GitHubToken` | ❌ | GitHub Gist Token (可選) |
| `Description` | ❌ | Gist 描述，預設 `"NICS blacklist uploaded by script"` |
| `NASPath` | ✅ | NAS 備份路徑 (e.g., `\\nas\share\NICS`) |
| `MailFrom` | ✅ | Email 寄件者 |
| `MailTo` | ✅ | Email 收件者清單 (逗號分隔) |
| `SMTPServer` | ✅ | SMTP 伺服器 |
| `SMTPPort` | ✅ | SMTP 連接埠 (25 或 587) |
| `SMTPUser` | ❌ | SMTP 使用者帳號 |
| `SMTPPass` | ❌ | SMTP 密碼 |
| `Proxy` | ❌ | HTTP/HTTPS Proxy |
| `ProxyRPB` | ❌ | Proxy 用於 GitHub Gist 上傳 |
| `ProxyCredential` | ❌ | Proxy 認證資訊 (PSCredential) |
| `UseSsl` | ❌ | Email 是否使用 SSL |
| `EnableEventLog` | ❌ | 是否寫入 Windows EventLog |
| `LineToken` | ❌ | LINE Notify Token |
| `SlackWebhook` | ❌ | Slack / Teams Webhook URL |

---

## 📜 執行範例
```powershell
.\NICS-Update.ps1 `
  -DST "C:\dns\NICS-Policy.txt" `
  -Token "your_api_token_here" `
  -GitHubToken "your_github_token_here" `
  -Description "NICS blacklist uploaded by script" `
  -NASPath "\\nas\share\NICS" `
  -MailFrom "alert@domain.com" `
  -MailTo "admin@domain.com" `
  -SMTPServer "smtp.domain.com" `
  -SMTPPort 587 `
  -SMTPUser "smtp_user" `
  -SMTPPass "smtp_password" `
  -UseSsl `
  -EnableEventLog `
  -LineToken "xxxxxxxxxx" `
  -SlackWebhook "https://hooks.slack.com/services/xxxxxx"

---

##  核心流程概覽
- 下載黑名單 (含 NAS 備份還原)
- 比對 SHA256 判斷是否更新
- 備份舊檔 & 覆蓋新檔
- 清除舊 Policy & 建立新 DNS Policy
- 格式轉換 (AdGuard / Pi-hole) 並備份至 NAS
- 上傳 GitHub Gist (僅 AdGuard / Pi-hole，僅更新異動檔案)
- 清理舊日誌 (保留最近 7 天)
- 多管道通知 (Email / EventLog / LINE / Slack/Teams)

---

## 📌 NICS-Update.ps1 核心流程圖

開始
│
└─► 下載黑名單 (NICS API / NAS 備份)
     │
     └─► 比對 SHA256
          │
          ├─► 無更新 → 結束
          │
          └─► 有更新
               │
               ├─► 備份舊檔
               │
               ├─► 覆蓋新檔
               │
               ├─► 清除舊 DNS Policy
               │
               ├─► 建立新 DNS Policy
               │
               ├─► 格式轉換
               │     ├─► AdGuard.txt
               │     └─► Pi-hole.txt
               │
               ├─► 備份至 NAS
               │
               ├─► 上傳 GitHub Gist (僅 AdGuard/Pi-hole)
               │
               ├─► 清理舊日誌 (保留 7 天)
               │
               └─► 多管道通知
                     ├─► Email
                     ├─► Windows Event Log
                     ├─► LINE Notify
                     └─► Slack / Teams Webhook
                          │
                          └─► 結束



---

```mermaid
flowchart TD
    A[開始] --> B[下載黑名單 NICS-Policy.tmp]
    B --> C[比對 SHA256 舊檔 vs 新檔]
    C -->|相同| D[發送通知: 無更新]
    D --> E[結束]
    C -->|不同| F[備份舊 NICS-Policy.txt]
    F --> G[覆蓋新檔 → NICS-Policy.txt]
    G --> H[清除舊 Policy]
    H --> I[重新建立 Policy]
    I --> J[格式轉換]
    J --> J1[AdGuard.txt]
    J --> J2[Pi-hole.txt]
    J1 --> K[備份至 NAS]
    J2 --> K
    K --> L[上傳 GitHub Gist]
    L --> L1[AdGuard.txt → Gist]
    L --> L2[Pi-hole.txt → Gist]
    L1 --> M[清理舊日誌 (本機 + NAS)]
    L2 --> M
    M --> N[發送通知 (Email / LINE / Slack / EventLog)]
    N --> E
