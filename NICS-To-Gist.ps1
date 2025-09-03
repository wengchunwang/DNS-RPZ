# ======================================================
# NICS-To-Gist.ps1 20250903-001
# �\��: �۰ʱN���a�ɮפW�ǩΧ�s�� GitHub Gist�A�åi�H�e�q�� Email
# �A��: �p����r�ɮס]�p NICS �¦W��B�]�w�ɵ��^�W�ǤΪ����޲z
# ======================================================
<#
.SYNOPSIS
    �ظm�¦W��B�W��/��s Gist�A�óz�L Email �q���C
.DESCRIPTION
    - �۰ʫظm�¦W���ɮ�
    - �W�ǩΧ�s GitHub Gist
    - �T�w���� URL + /raw URL
    - �o�e Email �q�������
.PARAMETER SRC
    �¦W���ɮ׸��| (�w�] C:\temp\NICS-RPZ.txt)
.PARAMETER Token
    GitHub Personal Access Token (����)
.PARAMETER Description
    Gist ������r
.PARAMETER From
    Email �H���
.PARAMETER To
    Email �����
.PARAMETER SmtpServer
    SMTP ���A��
.PARAMETER SmtpPort
    SMTP Port
.PARAMETER Proxy
    HTTP/HTTPS Proxy (���)
.PARAMETER ProxyCredential
    Proxy �b�K (���)
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
# �]�w LOG (�C�����)
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
        Add-Content -Path $logFile -Value "[$timestamp] �L�k�g�J NAS Log: $($_.Exception.Message)"
    }
}
# -----------------------------
# �M�z�W�L������ log
# -----------------------------
# ���� log �O�d 7 ��
Get-ChildItem -Path $logDir -Filter "NICS-Policy-*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
    ForEach-Object {
        try { Remove-Item $_.FullName -Force } 
        catch { Write-Log "�L�k�R���¥��� Log: $($_.FullName)�A��]: $($_.Exception.Message)" }
    }

# NAS log �O�d 30 ��
if ($NASPath) {
    Get-ChildItem -Path $NASPath -Filter "NICS-Policy-*.log" |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
        ForEach-Object {
            try { Remove-Item $_.FullName -Force } 
            catch { Write-Log "�L�k�R���� NAS Log: $($_.FullName)�A��]: $($_.Exception.Message)" }
        }
}

Write-Log "========== NICS-To-Gist.ps1 20250903-001 =========="
# -----------------------------
# 1?? �ظm�¦W���ɮ�
# -----------------------------
Write-Log "Step 1: �ظm�¦W���ɮ�"
if (-not (Test-Path $SRC)) {
    New-Item -Path $SRC -ItemType File | Out-Null
    Write-Log "        �إ߷s�ɮסG$SRC"
}

$TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$Content = Get-Content $SRC -Raw
$Content = "$Content"
Set-Content -Path $SRC -Value $Content -Encoding UTF8
Write-Log "        Ū���ç�s�ɮ׽s�X�G$SRC"

$FileName = [System.IO.Path]::GetFileName($SRC)

# -----------------------------
# 2?? �W��/��s GitHub Gist
# -----------------------------
Write-Log "Step 2: �W��/��s GitHub Gist"
$Headers = @{ Authorization = "token $Token"; "User-Agent" = "PowerShell" }

# �䴩 Proxy
$InvokeParams = @{
    Headers = $Headers
    ErrorAction = "Stop"
}
if ($Proxy)          { $InvokeParams.Proxy = $Proxy }
if ($ProxyCredential){ $InvokeParams.ProxyCredential = $ProxyCredential }

try {
    $gists = Invoke-RestMethod @InvokeParams -Uri "https://api.github.com/gists"
    Write-Log "        ���\���o�ϥΪ� Gists �C�� (�@ $($gists.Count) ��)"
} catch {
    Write-Log "        ���o Gists ���ѡG$($_.Exception.Message)"
    throw
}

# ���o�{�� Gists
$gists = Invoke-RestMethod @InvokeParams -Uri "https://api.github.com/gists"

# �ˬd�O�_�w���P�W�ɮ�
$existingGist = $gists | Where-Object { $_.files.PSObject.Properties.Name -contains $FileName }
$ContentJson = @{ content = $Content }

# JSON Body
if ($existingGist) {
    $GistID = $existingGist.id
    $Body   = @{ description = $Description; files = @{ $FileName = $ContentJson } } | ConvertTo-Json -Depth 5
	$Utf8Body = [System.Text.Encoding]::UTF8.GetBytes($Body)
    Invoke-RestMethod @InvokeParams -Uri "https://api.github.com/gists/$GistID" -Method Patch -Body $Utf8Body -ContentType "application/json"
    Write-Log "        �w��s Gist (ID=$GistID) �ɮסG$FileName"
} else {
    $Body  = @{ description = $Description; public = $true; files = @{ $FileName = $ContentJson } } | ConvertTo-Json -Depth 5
	$Utf8Body = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $resp = Invoke-RestMethod @InvokeParams -Uri "https://api.github.com/gists" -Method Post -Body $Utf8Body -ContentType "application/json"
    $GistID = $resp.id
    Write-Log "        �w�إ߷s�� Gist (ID=$GistID) �ɮסG$FileName"
}

# ���o Raw URL
#$RawUrl = $resp.files.$FileName.raw_url

# ���o�T�w Gist ���� URL
#$OwnerLogin = if ($resp.owner) { $resp.owner.login } else { $Token.Split('-')[0] }  # fallback
#$GistPageUrl = "https://gist.github.com/$OwnerLogin/$($resp.id)"
$OwnerLogin ="wengchunwang"

# �T�w URL
$GistPageUrl = "https://gist.github.com/$OwnerLogin/$GistID"
$GistRawUrl  = "$GistPageUrl/raw"

# -----------------------------
# 3?? �o�e Email �q��
# -----------------------------
Write-Log "Step 3: �o�e Email �q��"
$BodyEmail = @"
Gist �w�إ�/��s���\
�ɮצW�١G$FileName
Gist ���� URL�G$GistPageUrl
Raw URL�]�T�w�^�G$GistRawUrl
�ɶ��G$TimeStamp
"@
    
try {
    Send-MailMessage -From $MailFrom -To $MailTo -Subject "[NICS] �¦W��W�ǧ�s GitHub Gist �q��" -Body $BodyEmail `
        -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$false -Encoding UTF8
    Write-Log "        �w�o�e�q�� Email �� $MailTo"
} catch {
    Write-Log "        �o�e Email ���ѡG$($_.Exception.Message)"
}

# Write-Host "[INFO] �����AEmail �w�o�e�AGist URL �T�w�i�������o�̷s Raw ���e"
$end = Get-Date
$duration = ($end - $start).TotalSeconds
Write-Log "        ���ȧ����G$FileName �w�P�B�� GitHub Gist�A�`�Ӯ� $duration ��"
Write-Log "========== NICS-To-Gist.ps1 20250903-001 =========="