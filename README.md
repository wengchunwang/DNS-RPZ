# DNS-RPZ  
## DNS Sinkhole / DNS Firewalls / DNS RPZ  

### 📌 DNS RPZ（回應政策區域，Response Policy Zone）

---

## Windows Server (2016 以上)  

Windows Server 2016 以上提供 **DNS Policy** 設定功能，可達成阻擋特定域名的效果。  

常用指令：  

| 指令 | 說明 |
|------|------|
| `Get-DnsServerQueryResolutionPolicy` | 取得 DNS 伺服器現有網域查詢解析規則 |
| `Add-DnsServerQueryResolutionPolicy` | 新增網域查詢解析規則至 DNS 伺服器 |
| `Remove-DnsServerQueryResolutionPolicy` | 從 DNS 伺服器中刪除網域查詢解析規則 |

---

## Bind DNS Server (9.10 以上)  

Bind 9.10 以上提供 **RPZ (Response Policy Zone)** 功能。  

### `named.conf.options`  
```conf
options {
  response-policy {
    zone "local.rpz";
  };
};
```

### `named.conf.default-zones`  
```conf
zone "local.rpz" {
  type master;
  file "zones/db-rpz-local";
  allow-query { localhost; };
  allow-transfer { localhost; };
};
```



# Windows PowerShell Scripts

專案包含三個 PowerShell 腳本，用於處理、轉換及更新 NICS 黑名單，並可自動上傳至 GitHub Gist 或發送 Email 通知。

## 目錄結構

```text
NICS-PowerShell-Scripts/
│
├─ NICS-To-AdGuard.ps1       # 將原始黑名單轉換成 AdGuard 格式
├─ NICS-To-Gist.ps1          # 將黑名單上傳至 GitHub Gist
├─ NICS-Update.ps1           # 自動更新，整合轉換 + 上傳 + 日誌
├─ README.md                 # 專案說明文件
└─ Logs/                     # 本機及 NAS 日誌存放資料夾
```

## 目錄

1. [NICS-Update.ps1](#nics-updateps1)
2. [NICS-To-AdGuard.ps1](#nics-to-adguardps1)  
3. [NICS-To-Gist.ps1](#nics-to-gistps1)  

---

## 腳本功能

### 1. NICS-Update.ps1
- 自動檢查黑名單更新
- 寫入 Log（本機與 NAS）
- 發送 Email 通知（可選）
- 自動清理本機 7 日以上 Log、NAS 30 日以上 Log

### 2. NICS-To-AdGuard.ps1
- 檢查原始黑名單是否存在
- 計算 SHA256 確認是否有更新
- 轉換為 AdGuard 格式，自動加上 header 與每行 `||...^`
- 統計筆數並寫入本機及 NAS Log
- 更新 SHA256 紀錄檔
- 發送 Email 通知（可選）

### 3. NICS-To-Gist.ps1
- 將黑名單（ AdGuard 格式）上傳至 GitHub Gist
- 支援自動更新 Log 與 SHA256 紀錄
- 發送 Email 通知（可選）
- 可搭配 NICS-Update.ps1 自動執行

## 腳本執行流程

```text
          ┌───────────────────────────┐
          │   NICS-Update.ps1         │
          │ (檢查黑名單更新 + 執行)  │
          └─────────────┬────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
┌───────▼────────┐              ┌───────▼────────┐
│ NICS-To-AdGuard│              │ NICS-To-Gist   │
│ .ps1           │              │ .ps1           │
│ 轉換黑名單      │              │ 上傳至 GitHub │
│ 產生 AdGuard   │              │ Gist           │
│ 格式 & Log     │              │ Log            │
└───────┬────────┘              └───────┬────────┘
        │                               │
        └─────────────┬─────────────────┘
                      │
               ┌──────▼───────┐
               │ Email 通知    │
               │ (可選)       │
               └──────────────┘
```

**使用方式：**

```powershell
.\NICS-Update.ps1      -SRC "C:\Temp\blacklist.txt" `
                       -DST "C:\Temp\AdGuard.txt" `
                       -NASPath "\\NAS\Logs" `
                       -MailFrom "noreply@example.com" `
                       -MailTo "admin@example.com" `
                       -SMTPServer "smtp.example.com" `
                       -SMTPPort 25

## 使用說明

1. 編輯腳本參數，例如黑名單來源 `$SRC`、轉換後檔案 `$DST`、NAS 路徑 `$NASPath`、Email 設定等。
2. 直接執行 `NICS-Update.ps1` 即可自動完成檢查、轉換、上傳與通知。
3. Log 會自動清理（本機保留 3 日，NAS 保留 30 日）。

## 注意事項

- 確保 PowerShell 執行策略允許執行本地腳本 (`Set-ExecutionPolicy RemoteSigned`)。
- 若使用 Email 通知，需正確設定 SMTP 參數。
- NAS Log 需可寫入權限。

