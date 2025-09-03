# ======================================================
# NICS-To-AdGuard.ps1 20250903-005
# 功能:
#  - 檢查原始黑名單是否存在 ($SRC)。
#  - 比對 SHA256 確認是否有更新，無更新則跳過（仍記錄耗時）。
#  - 轉換為 AdGuard 家用格式，自動加上 header 與每行 ||...^。
#  - 自動移除來源中的 http:// 與 https:// 前綴。
#  - 統計筆數 並寫入 log。
#  - 寫入本機及 NAS log（如果指定 $NASPath）。
#  - 更新 SHA256 紀錄檔。
#  - 成功後自動複製 $DST 至 NAS (AdGuard.txt)。
#  - 發送 Email 通知（僅在有更新時）。
#  - 輸出完成訊息與耗時統計。
# ======================================================
param (
    [string]$SRC,       # 原始黑名單
    [string]$DST,       # 轉換後檔案
    [string]$NASPath,   # NAS LOG 與輸出目錄
    [string]$MailFrom,
    [string]$MailTo,
    [string]$SMTPServer,
    [int]$SMTPPort
)
$start = Get-Date
# -----------------------------
# 設定 LOG (每日分檔)
# -----------------------------
$logFile    = "C:\TEMP\NICS-Policy-$(Get-Date -Format yyyyMMdd).log"
$logFileNAS = if ($NASPath) { Join-Path $NASPath "NICS-Policy-$(Get-Date -Format yyyyMMdd).log" } else { $null }

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy/MM/dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] $Message"
    if ($logFileNAS) {
        try {
            Add-Content -Path $logFileNAS -Value "[$timestamp] $env:COMPUTERNAME $Message" -ErrorAction Stop
        } catch {
            Add-Content -Path $logFile -Value "[$timestamp] 無法寫入 NAS Log: $($_.Exception.Message)"
        }
    }
}
# -----------------------------
# 清理超過期限的 log
# -----------------------------
# 本機 log 保留 7 日
Get-ChildItem -Path $logDir -Filter "NICS-Policy-*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    ForEach-Object {
        try { Remove-Item $_.FullName -Force } 
        catch { Write-Log "無法刪除舊本機 Log: $($_.FullName)，原因: $($_.Exception.Message)" }
    }

# NAS log 保留 30 日
if ($NASPath) {
    Get-ChildItem -Path $NASPath -Filter "NICS-Policy-*.log" |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        ForEach-Object {
            try { Remove-Item $_.FullName -Force } 
            catch { Write-Log "無法刪除舊 NAS Log: $($_.FullName)，原因: $($_.Exception.Message)" }
        }
}

$ErrorActionPreference = "Stop"

Write-Log "========== NICS-To-AdGuard.ps1 20250903-005 =========="

# -----------------------------
# 檢查原始檔是否存在
# -----------------------------
Write-Log "Step 1: 檢查原始檔是否存在"
if (-not (Test-Path $SRC)) {
    Write-Log "        來源檔不存在: $SRC"
    $end = Get-Date
    $duration = "{0:N2}" -f (($end - $start).TotalSeconds)
    Write-Log "        [INFO] 結束，來源不存在，總耗時 $duration 秒"
    Write-Log "========== NICS-To-AdGuard.ps1 20250903-005 =========="
    exit
}

# -----------------------------
# 計算原始檔 SHA256
# -----------------------------
Write-Log "Step 2: 計算原始檔 SHA256"
$hashFile = "$SRC.sha256"
$sha256   = Get-FileHash -Path $SRC -Algorithm SHA256 | Select-Object -ExpandProperty Hash
$oldHash  = if (Test-Path $hashFile) { Get-Content $hashFile -ErrorAction SilentlyContinue } else { "" }

if ($sha256 -eq $oldHash) {
    Write-Log "        黑名單無變更，跳過轉換"
    $end = Get-Date
    $duration = "{0:N2}" -f (($end - $start).TotalSeconds)
    Write-Log "        [INFO] 完成（無變更），總耗時 $duration 秒"
    Write-Log "========== NICS-To-AdGuard.ps1 20250903-005 =========="
    exit
}

# -----------------------------
# 轉換 AdGuard 格式並統計筆數
# -----------------------------
Write-Log "Step 3: 轉換 AdGuard 格式並統計筆數"

$lines = Get-Content $SRC | Where-Object { $_.Trim() -ne "" } |
    ForEach-Object { ($_ -replace '^(https?://)', '') }

$recordCount = $lines.Count

$AdGuardHeader = @(
    "! Title: AdGuard.txt"
    "! Last modified: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    "!"
)
$AdGuardBody = $lines | ForEach-Object { "||$_^" }

# 合併 header 與 body
$AdGuardContent = $AdGuardHeader + $AdGuardBody
Set-Content -Path $DST -Value $AdGuardContent -Encoding UTF8

Write-Log "        黑名單已轉換為 AdGuard 格式: $DST，總筆數: $recordCount"

# 更新 SHA256
Set-Content -Path $hashFile -Value $sha256

# -----------------------------
# 複製至 NAS (如果指定)
# -----------------------------
if ($NASPath) {
    try {
        $nasFile = Join-Path $NASPath "AdGuard.txt"
        Copy-Item -Path $DST -Destination $nasFile -Force
        Write-Log "        已複製 AdGuard 黑名單至 NAS: $nasFile"
    } catch {
        Write-Log "        複製至 NAS 失敗: $($_.Exception.Message)"
    }
}

# -----------------------------
# 發送 Email 通知（僅在有更新）
# -----------------------------
if ($MailFrom -and $MailTo -and $SMTPServer) {
    $BodyEmail = @"
黑名單已更新並轉換為 AdGuard 格式
檔案名稱：$DST
總筆數：$recordCount
時間：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
    try {
        Send-MailMessage -From $MailFrom -To $MailTo -Subject "[NICS] 黑名單已更新並轉換為 AdGuard 格式" `
            -Body $BodyEmail -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$false -Encoding UTF8
        Write-Log "        Email 已發送給 $MailTo"
    } catch {
        Write-Log "        Email 發送失敗: $($_.Exception.Message)"
    }
}

# -----------------------------
# 完成訊息與耗時
# -----------------------------
$end = Get-Date
$duration = "{0:N2}" -f (($end - $start).TotalSeconds)
Write-Log "        [INFO] 完成，轉換檔案已生成: $DST，總耗時 $duration 秒，總筆數 $recordCount"
Write-Log "========== NICS-To-AdGuard.ps1 20250903-005 =========="

# Write-Host "[INFO] 完成，轉換檔案已生成: $DST，總筆數: $recordCount"
