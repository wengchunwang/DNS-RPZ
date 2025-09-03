# ======================================================
# NICS-To-Gist.ps1 20250903-001
# 功能: 自動將本地檔案上傳或更新至 GitHub Gist，並可寄送通知 Email
# 適用: 小型文字檔案（如 NICS 黑名單、設定檔等）上傳及版本管理
# ======================================================
<#
.SYNOPSIS
    建置黑名單、上傳/更新 Gist，並透過 Email 通知。
.DESCRIPTION
    - 自動建置黑名單檔案
    - 上傳或更新 GitHub Gist
    - 固定頁面 URL + /raw URL
    - 發送 Email 通知收件者
.PARAMETER SRC
    黑名單檔案路徑 (預設 C:\temp\NICS-RPZ.txt)
.PARAMETER Token
    GitHub Personal Access Token (必填)
.PARAMETER Description
    Gist 說明文字
.PARAMETER From
    Email 寄件者
.PARAMETER To
    Email 收件者
.PARAMETER SmtpServer
    SMTP 伺服器
.PARAMETER SmtpPort
    SMTP Port
.PARAMETER Proxy
    HTTP/HTTPS Proxy (選填)
.PARAMETER ProxyCredential
    Proxy 帳密 (選填)
#>
param (
    [string]$SRC,
    [Parameter(Mandatory=$true)][string]$Token,
	[string]$NASPath,
    [string]$Description,
    [string]$MailFrom,
    [string]$MailTo,
    [string]$SMTPServer,
    [int]$SMTPPort,
    [string]$Proxy = $null,
    [PSCredential]$ProxyCredential = $null
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

Write-Log "========== NICS-To-Gist.ps1 20250903-001 =========="
# -----------------------------
# 1?? 建置黑名單檔案
# -----------------------------
Write-Log "Step 1: 建置黑名單檔案"
if (-not (Test-Path $SRC)) {
    New-Item -Path $SRC -ItemType File | Out-Null
    Write-Log "        建立新檔案：$SRC"
}

$TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$Content = Get-Content $SRC -Raw
$Content = "$Content"
Set-Content -Path $SRC -Value $Content -Encoding UTF8
Write-Log "        讀取並更新檔案編碼：$SRC"

$FileName = [System.IO.Path]::GetFileName($SRC)

# -----------------------------
# 2?? 上傳/更新 GitHub Gist
# -----------------------------
Write-Log "Step 2: 上傳/更新 GitHub Gist"
$Headers = @{ Authorization = "token $Token"; "User-Agent" = "PowerShell" }

# 支援 Proxy
$InvokeParams = @{
    Headers = $Headers
    ErrorAction = "Stop"
}
if ($Proxy)          { $InvokeParams.Proxy = $Proxy }
if ($ProxyCredential){ $InvokeParams.ProxyCredential = $ProxyCredential }

try {
    $gists = Invoke-RestMethod @InvokeParams -Uri "https://api.github.com/gists"
    Write-Log "        成功取得使用者 Gists 列表 (共 $($gists.Count) 筆)"
} catch {
    Write-Log "        取得 Gists 失敗：$($_.Exception.Message)"
    throw
}

# 取得現有 Gists
$gists = Invoke-RestMethod @InvokeParams -Uri "https://api.github.com/gists"

# 檢查是否已有同名檔案
$existingGist = $gists | Where-Object { $_.files.PSObject.Properties.Name -contains $FileName }
$ContentJson = @{ content = $Content }

# JSON Body
if ($existingGist) {
    $GistID = $existingGist.id
    $Body   = @{ description = $Description; files = @{ $FileName = $ContentJson } } | ConvertTo-Json -Depth 5
	$Utf8Body = [System.Text.Encoding]::UTF8.GetBytes($Body)
    Invoke-RestMethod @InvokeParams -Uri "https://api.github.com/gists/$GistID" -Method Patch -Body $Utf8Body -ContentType "application/json"
    Write-Log "        已更新 Gist (ID=$GistID) 檔案：$FileName"
} else {
    $Body  = @{ description = $Description; public = $true; files = @{ $FileName = $ContentJson } } | ConvertTo-Json -Depth 5
	$Utf8Body = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $resp = Invoke-RestMethod @InvokeParams -Uri "https://api.github.com/gists" -Method Post -Body $Utf8Body -ContentType "application/json"
    $GistID = $resp.id
    Write-Log "        已建立新的 Gist (ID=$GistID) 檔案：$FileName"
}

# 取得 Raw URL
#$RawUrl = $resp.files.$FileName.raw_url

# 取得固定 Gist 頁面 URL
#$OwnerLogin = if ($resp.owner) { $resp.owner.login } else { $Token.Split('-')[0] }  # fallback
#$GistPageUrl = "https://gist.github.com/$OwnerLogin/$($resp.id)"
$OwnerLogin ="wengchunwang"

# 固定 URL
$GistPageUrl = "https://gist.github.com/$OwnerLogin/$GistID"
$GistRawUrl  = "$GistPageUrl/raw"

# -----------------------------
# 3?? 發送 Email 通知
# -----------------------------
Write-Log "Step 3: 發送 Email 通知"
$BodyEmail = @"
Gist 已建立/更新成功
檔案名稱：$FileName
Gist 頁面 URL：$GistPageUrl
Raw URL（固定）：$GistRawUrl
時間：$TimeStamp
"@
    
try {
    Send-MailMessage -From $MailFrom -To $MailTo -Subject "[NICS] 黑名單上傳更新 GitHub Gist 通知" -Body $BodyEmail `
        -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$false -Encoding UTF8
    Write-Log "        已發送通知 Email 至 $MailTo"
} catch {
    Write-Log "        發送 Email 失敗：$($_.Exception.Message)"
}

# Write-Host "[INFO] 完成，Email 已發送，Gist URL 固定可直接取得最新 Raw 內容"
$end = Get-Date
$duration = ($end - $start).TotalSeconds
Write-Log "        任務完成：$FileName 已同步至 GitHub Gist，總耗時 $duration 秒"
Write-Log "========== NICS-To-Gist.ps1 20250903-001 =========="