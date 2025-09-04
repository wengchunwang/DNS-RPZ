# NICS-To-Blacklist

將原始黑名單轉換為多種常用格式（支援 AdGuard、Pi-hole，未來可擴充）。

---

## 功能
- 檢查來源黑名單是否存在。
- 依指定格式轉換：AdGuard、Pi-hole、或 All。
- 支援 `-Format All` 同時輸出兩種格式檔案。
- 自動比對 SHA256，來源未變更時自動跳過。
- 本機 LOG 保留 3 日，NAS LOG 保留 30 日。
- 可選擇寄送 Email 通知。

---

## 使用方式

### 轉換為 AdGuard 格式
```powershell
.\NICS-To-Blacklist.ps1 -SRC C:\TEMP\NICS-Policy.txt -DST C:\TEMP\AdGuard.txt -Format AdGuard
```

### 轉換為 Pi-hole 格式
```powershell
.\NICS-To-Blacklist.ps1 -SRC C:\TEMP\NICS-Policy.txt -DST C:\TEMP\PiHole.txt -Format Pi-hole
```

### 同時轉換為 AdGuard 與 Pi-hole 格式
```powershell
.\NICS-To-Blacklist.ps1 -SRC C:\TEMP\NICS-Policy.txt -DST C:\TEMP\Blacklist.txt -Format All
```

## 執行後會輸出兩個檔案：
- C:\TEMP\Blacklist-AdGuard.txt
- C:\TEMP\Blacklist-PiHole.txt

## Email 通知（可選）
```powershell
.\NICS-To-Blacklist.ps1 `
  -SRC C:\TEMP\NICS-Policy.txt `
  -DST C:\TEMP\Blacklist.txt `
  -Format All `
  -MailFrom admin@example.com `
  -MailTo it@example.com `
  -SMTPServer smtp.example.com -SMTPPort 25
```

## LOG 管理
- 本機 LOG (C:\TEMP\NICS-Policy-YYYYMMDD.log) 保留 3 日。
- NAS LOG (\\NAS\BlackList\NICS-Policy-YYYYMMDD.log) 保留 30 日。
