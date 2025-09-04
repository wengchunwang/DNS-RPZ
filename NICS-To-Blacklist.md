# NICS Blacklist Tools

本專案提供自動化黑名單處理工具，將原始黑名單轉換成 **AdGuard** 或 **Pi-hole** 可用格式，並支援自動紀錄與清理 log、Email 通知。

---

## 主要腳本

### `NICS-To-Blacklist.ps1`
- 功能：
  - 檢查原始黑名單是否存在。
  - 比對 SHA256 確認是否有更新。
  - 轉換為指定格式：
    - **AdGuard**  
      ```
      ||domain.com^
      ||ads.example.net^
      ```
    - **Pi-hole**  
      ```
      0.0.0.0 domain.com
      0.0.0.0 ads.example.net
      ```
  - 統計筆數並寫入 log。
  - 自動清理 log：
    - 本機 log 保留 **3 日**。
    - NAS log 保留 **30 日**。
  - 可選的 Email 通知。
  - 輸出完成訊息與耗時統計。

---

## 使用方式

### 1. 轉換為 AdGuard 格式
```powershell
.\NICS-To-Blacklist.ps1 -SRC C:\TEMP\NICS-Policy.txt -DST C:\TEMP\AdGuard.txt -Format AdGuard
