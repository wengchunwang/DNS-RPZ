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
