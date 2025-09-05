# ======================================================
# NICS-To-Blacklist.ps1
# 功能:
#  - 檢查原始黑名單是否存在 ($SRC)。
#  - 比對 SHA256 確認是否有更新，無更新則跳過（仍紀錄耗時）。
#  - 轉換為指定格式 (AdGuard / Pi-hole / All)。
#  - 統計筆數並寫入 LOG。
#  - 自動清理 LOG：
#       - 本機 log 保留 3 日
#       - NAS log 保留 30 日
#  - 發送 Email 通知（可選）。
#  - 複製轉換檔至 NAS（可選）。
# ======================================================

param (
    [string]$SRC,       # 原始黑名單
    [string]$DST,       # 轉換後檔案基底名稱 (不含副檔名)
    [string]$NASPath,   # NAS LOG 目錄
    [ValidateSet("AdGuard","Pi-hole","All")]
    [string]$Format = "AdGuard",
    [string]$MailFrom,
    [string]$MailTo,
    [string]$SMTPServer,
    [int]$SMTPPort = 25,
    [switch]$UseSsl
)

$start = Get-Date
$version = "2025-09-05.004"

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
$logDir = Split-Path $logFile
# 本機 log 保留 3 日
Get-ChildItem -Path $logDir -Filter "NICS-Policy-*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
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

# -----------------------------
# 主流程
# -----------------------------
Write-Log "========== NICS-To-Blacklist.ps1 $version =========="

# 檢查原始檔
Write-Log "Step 1: 檢查原始檔是否存在"
if (-not (Test-Path $SRC)) {
    Write-Log "        來源檔不存在: $SRC"
    $duration = (New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
    Write-Log "        [INFO] 結束，耗時 $duration 秒"
    Write-Log "========== NICS-To-Blacklist.ps1 END =========="
    exit
}

# -----------------------------
# 讀取與清理內容
# -----------------------------
$rawContent = [IO.File]::ReadAllText($SRC)
$rawContent = ($rawContent -split "`r?`n" | Where-Object { $_.Trim() -ne "" }) -join "`n"

if (-not $rawContent) {
    Write-Log "來源檔為空，停止處理"
    Write-Log "========== NICS-To-Blacklist.ps1 END =========="
    exit
}

# -----------------------------
# 計算 SHA256
# -----------------------------
Write-Log "Step 2: 計算原始檔 SHA256"

$sha256 = Get-FileHash -InputStream ([System.IO.MemoryStream]::new(
    [System.Text.Encoding]::UTF8.GetBytes($rawContent)
)) -Algorithm SHA256 | Select-Object -ExpandProperty Hash

# 原本寫法
#$hashFile   = "$SRC.$Format.sha256"
# 新寫法：統一簡化格式名稱
$hashFile   = Join-Path (Split-Path $SRC) "$Format.sha256"

$oldHash    = if (Test-Path $hashFile) { Get-Content $hashFile -ErrorAction SilentlyContinue } else { "" }

# 若來源沒變更 + 轉換檔已存在，則跳過
if ($sha256 -eq $oldHash) {
    Write-Log "        黑名單無變更，跳過轉換"
    $duration = (New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
    Write-Log "        [INFO] 結束（無變更），耗時 $duration 秒"
    Write-Log "========== NICS-To-Blacklist.ps1 END =========="
    exit
}

# -----------------------------
# 轉換格式
# -----------------------------
Write-Log "Step 3: 轉換為 $Format 格式"

$lines = $rawContent -split "`n"
$recordCount = $lines.Count

function Get-OutputPath {
    param([string]$basePath,[string]$fmt)
    $ext = if ($fmt -eq "AdGuard") { ".txt" } elseif ($fmt -eq "Pi-hole") { ".txt" } else { "$fmt.txt" }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($basePath)
    $dir = [System.IO.Path]::GetDirectoryName($basePath)
    return Join-Path $dir "$baseName$ext"
}

$targets = @()
switch ($Format) {
    "AdGuard" { $targets = @("AdGuard") }
    "Pi-hole" { $targets = @("Pi-hole") }
    "All" { $targets = @("AdGuard","Pi-hole") }
}

foreach ($fmt in $targets) {
    $outFile = Get-OutputPath -basePath $DST -fmt $fmt
    switch ($fmt) {
        "AdGuard" {
            $Header = @(
                "! ------------------------------------[UPDATE]--------------------------------------"
                "! Title: AdGuard DNS filter"
                "! Description: List composed of several filters"
                "! Version: $version"
                "! Homepage: https://gist.github.com/wengchunwang"
                "! Last modified: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                "! -------------------------------------[INFO]---------------------------------------"
                "!"
                "! ------------------------------------[FILTERS]-------------------------------------"
            )
            $Body = $lines | ForEach-Object { "||$_^" }
            $Output = $Header + $Body + @("")
        }
        "Pi-hole" {
            $Header = @(
                "# ------------------------------------[UPDATE]--------------------------------------"
                "# Title: Pi-hole DNS filter"
                "# Description: List composed of several filters"
                "# Version: $version"
                "# Homepage: https://gist.github.com/wengchunwang"
                "# Last modified: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                "# -------------------------------------[INFO]---------------------------------------"
                "#"
                "# ------------------------------------[FILTERS]-------------------------------------"
            )
            $Body = $lines | ForEach-Object { "0.0.0.0 $_" }
            $Output = $Header + $Body + @("")
        }
    }

    Set-Content -Path $outFile -Value $Output -Encoding UTF8
    Write-Log "        黑名單已轉換為 $fmt 格式: $outFile，總筆數: $recordCount"
}

# 更新 SHA256
Set-Content -Path $hashFile -Value $sha256

# -----------------------------
# 發送 Email（可選）
# -----------------------------
if ($MailFrom -and $MailTo -and $SMTPServer) {
    $subjectFmt = ($targets -join ", ")
    $subject    = "[NICS] 黑名單已更新 ($subjectFmt)"

    $outFiles = foreach ($fmt in $targets) { Get-OutputPath -basePath $DST -fmt $fmt }

    $BodyEmail = @"
黑名單已更新並轉換為 $subjectFmt 格式
輸出檔案：
$outFiles

總筆數：$recordCount
時間：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

    try {
        Send-MailMessage -From $MailFrom -To $MailTo -Subject $subject `
            -Body $BodyEmail -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$UseSsl -Encoding UTF8
        Write-Log "        Email 已發送給 $MailTo"
    } catch {
        Write-Log "        Email 發送失敗: $($_.Exception.Message)"
    }
}

$end = Get-Date
$duration = ($end - $start).TotalSeconds
Write-Log "        [INFO] 完成，總耗時 $duration 秒，總筆數 $recordCount"
Write-Log "========== NICS-To-Blacklist.ps1 END =========="
