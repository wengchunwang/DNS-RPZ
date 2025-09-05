# ======================================================
# NICS-Update.ps1 
# 功能: 自動下載 NICS 黑名單，更新 DNS QueryResolutionPolicy
#       僅在黑名單有更新時才重建 Policy，完成後發送 Email
# 適用: 少量黑名單 (<500)，方便直接檢視與管理
# ======================================================
param(
    [string]$DST,
    [string]$Token,
    [string]$NASPath,
    [string]$MailFrom,
    [string]$MailTo,
    [string]$SMTPServer,
    [int]$SMTPPort,
    [string]$proxy
)

$start = Get-Date
$version = "2025-09-05.004"
$source = "https://ironcloak.nics.nat.gov.tw/api/get_windows_blacklist_dn/$Token"
# -----------------------------
# 設定 LOG (每日分檔)
# -----------------------------
$logFile    = "C:\TEMP\NICS-Policy-$(Get-Date -Format yyyyMMdd).log"
$logFileNAS = if ($NASPath) { Join-Path $NASPath "NICS-Policy-$(Get-Date -Format yyyyMMdd).log" } else { $null }

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy/MM/dd HH:mm:ss"
    Add-Content -Path $logFile -Value "[$timestamp] $Message"
    try {
        if ($logFileNAS) {
            Add-Content -Path $logFileNAS -Value "[$timestamp] $env:COMPUTERNAME $Message" -ErrorAction Stop
        }
    } catch {
        Add-Content -Path $logFile -Value "[$timestamp] 無法寫入 NAS Log: $($_.Exception.Message)"
    }
}

# -----------------------------
# 清理超過期限的 log
# -----------------------------

# 本機 log 保留 7 日
$logDir = Split-Path $logFile
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

# 建立暫存資料夾
if (!(Test-Path "C:\TEMP")) { New-Item -ItemType Directory -Path "C:\TEMP" | Out-Null }
Write-Log "========== NICS-Update.ps1 $version =========="

# Step 1: 下載黑名單到暫存檔
Write-Log "Step 1: 下載黑名單到暫存檔"
$tmpFile = "$DST.tmp"
try {
    if ($proxy) {
        Invoke-WebRequest -Uri $source -OutFile $tmpFile -Proxy $proxy -ErrorAction Stop
    } else {
        Invoke-WebRequest -Uri $source -OutFile $tmpFile -ErrorAction Stop
    }
    Write-Log "        成功下載黑名單到暫存檔"
} catch {
    Write-Log "        下載失敗: $_"
    Send-MailMessage -To $MailTo -From $MailFrom -Subject "[NICS] 黑名單更新失敗" `
                     -Body "下載黑名單失敗：$($_)" -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$false -Encoding UTF8
    exit 1
}

# Step 2: 比對是否更新
Write-Log "Step 2: 比對是否更新"
$needUpdate = $true
if (Test-Path $DST) {
    $hashOld = Get-FileHash $DST -Algorithm SHA256
    $hashNew = Get-FileHash $tmpFile -Algorithm SHA256
    if ($hashOld.Hash -eq $hashNew.Hash) {
        $needUpdate = $false
        Write-Log "        黑名單未變更，無需更新 Policy"
        Remove-Item $tmpFile -Force
    }
}

if ($needUpdate) {
    # 備份舊檔
    if (Test-Path $DST) { Copy-Item $DST "$DST.bak" -Force }

    # 替換新檔
    Move-Item -Path $tmpFile -Destination $DST -Force
    Write-Log "        黑名單有更新，開始建立 Policy"

    # Step 3: 清除舊有 Policy
    Write-Log "Step 3: 清除舊有 Policy"
    Get-DnsServerQueryResolutionPolicy | Where-Object { $_.Name -like "NICS-*" } | Remove-DnsServerQueryResolutionPolicy -Force

    # Step 4: 讀取清單、過濾與去重
    Write-Log "Step 4: 讀取清單、過濾與去重"
    $domains = Get-Content $DST | Where-Object { $_ -and ($_ -match "^[a-zA-Z0-9.-]+$") } | Sort-Object -Unique

    # Step 5: 批次建立 Policy
    Write-Log "Step 5: 批次建立 Policy"
    $success = 0
    $fail    = 0
    foreach ($line in $domains) {
        try {
            Add-DnsServerQueryResolutionPolicy -Name "NICS-$line" -Action DENY -FQDN "EQ,*.$line" -PassThru -ErrorAction Stop | Out-Null
            $success++
        } catch {
            $fail++
            Write-Log "        新增失敗: $line"
        }
    }

    Write-Log "        成功新增 $success 筆，失敗 $fail 筆"
}

# Step 6: 統一發送 Email
Write-Log "Step 6: 發送 Email 通知"
$body = if ($needUpdate) {
    "黑名單更新完成`n成功新增: $success 筆`n新增失敗: $fail 筆`n耗時: $((Get-Date) - $start).TotalSeconds 秒"
} else {
    "黑名單未變更，無需更新 Policy"
}

try {
    Send-MailMessage -To $MailTo -From $MailFrom -Subject "[NICS] 黑名單更新狀態" `
                     -Body $body -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$false -Encoding UTF8
    Write-Log "        已發送 Email 通知 $MailTo"
} catch {
    Write-Log "        Email 發送失敗: $_"
}

$end = Get-Date
$duration = ($end - $start).TotalSeconds
Write-Log "完成執行，總耗時 $duration 秒"
Write-Log "========== NICS-Update.ps1 END =========="
