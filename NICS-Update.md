# NICS-Update.ps1

## 📌 簡介
`NICS-Update.ps1` 是一個自動化腳本，用來 **下載 NICS 黑名單、建立 DNS Policy、轉換格式 (AdGuard / Pi-hole)、同步 NAS 備份、發送通知**。  
主要適用於 Windows Server 搭配 DNS Server 角色。

---

## 🚀 功能
- 從 NICS API 下載最新黑名單 (支援 Proxy)。
- 比對 SHA256 碼，僅在有異動時才更新。
- 自動清除舊的 `NICS-*` DNS Policy 並重新建立。
- 將黑名單轉換為 **AdGuard** 與 **Pi-hole** 格式。
- 支援 **NAS 備份** (黑名單與轉換檔)。
- 保留最近 7 天的 Log，舊檔自動清理。
- 提供多管道通知：
  - 📧 Email
  - 📝 Event Log
  - 📲 LINE Notify
  - 💬 Slack / Teams Webhook

---

## ⚙️ 參數說明
| 參數 | 必要 | 說明 |
|------|------|------|
| `DST` | ✅ | 黑名單輸出檔案路徑 (e.g., `C:\dns\NICS-Policy.txt`) |
| `Token` | ✅ | NICS API Token |
| `NASPath` | ✅ | NAS 備份路徑 (e.g., `\\nas\share\NICS`) |
| `MailFrom` | ✅ | 發送通知 Email 的寄件者 |
| `MailTo` | ✅ | 收件者清單 (逗號分隔) |
| `SMTPServer` | ✅ | SMTP 伺服器 |
| `SMTPPort` | ✅ | SMTP 連接埠 (通常 25 或 587) |
| `SMTPUser` | ❌ | SMTP 使用者帳號 |
| `SMTPPass` | ❌ | SMTP 密碼 |
| `PROXY` | ❌ | Proxy 伺服器 (e.g., `http://proxy:8080`) |
| `UseSsl` | ❌ | 是否使用 SSL 發送 Email |
| `EnableEventLog` | ❌ | 是否啟用 Windows EventLog |
| `LineToken` | ❌ | LINE Notify Token |
| `SlackWebhook` | ❌ | Slack / Teams Webhook URL |

---

## 📜 執行方式
```powershell
# 基本執行
.\NICS-Update.ps1 `
  -DST "C:\dns\NICS-Policy.txt" `
  -Token "your_api_token_here" `
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

# NICS-Update.ps1 執行流程圖
開始
│
└─► 下載黑名單
     │
     └─► 比對 SHA256
          │
          └─► 更新 & 格式轉換
               │
               ├─► AdGuard.txt
               └─► Pi-hole.txt
                    │
                    └─► 備份 / 上傳 Gist
                         │
                         └─► 發送通知
                              │
                              └─► 結束




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
