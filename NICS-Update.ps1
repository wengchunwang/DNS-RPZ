# ======================================================
# NICS-Update.ps1 
# �\��: �۰ʤU�� NICS �¦W��A��s DNS QueryResolutionPolicy
#       �Ȧb�¦W�榳��s�ɤ~���� Policy�A������o�e Email
# �A��: �ֶq�¦W�� (<500)�A��K�����˵��P�޲z
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
$logDir = Split-Path $logFile
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

# �إ߼Ȧs��Ƨ�
if (!(Test-Path "C:\TEMP")) { New-Item -ItemType Directory -Path "C:\TEMP" | Out-Null }
Write-Log "========== NICS-Update.ps1 $version =========="

# Step 1: �U���¦W���Ȧs��
Write-Log "Step 1: �U���¦W���Ȧs��"
$tmpFile = "$DST.tmp"
try {
    if ($proxy) {
        Invoke-WebRequest -Uri $source -OutFile $tmpFile -Proxy $proxy -ErrorAction Stop
    } else {
        Invoke-WebRequest -Uri $source -OutFile $tmpFile -ErrorAction Stop
    }
    Write-Log "        ���\�U���¦W���Ȧs��"
} catch {
    Write-Log "        �U������: $_"
    Send-MailMessage -To $MailTo -From $MailFrom -Subject "[NICS] �¦W���s����" `
                     -Body "�U���¦W�楢�ѡG$($_)" -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$false -Encoding UTF8
    exit 1
}

# Step 2: ���O�_��s
Write-Log "Step 2: ���O�_��s"
$needUpdate = $true
if (Test-Path $DST) {
    $hashOld = Get-FileHash $DST -Algorithm SHA256
    $hashNew = Get-FileHash $tmpFile -Algorithm SHA256
    if ($hashOld.Hash -eq $hashNew.Hash) {
        $needUpdate = $false
        Write-Log "        �¦W�楼�ܧ�A�L�ݧ�s Policy"
        Remove-Item $tmpFile -Force
    }
}

if ($needUpdate) {
    # �ƥ�����
    if (Test-Path $DST) { Copy-Item $DST "$DST.bak" -Force }

    # �����s��
    Move-Item -Path $tmpFile -Destination $DST -Force
    Write-Log "        �¦W�榳��s�A�}�l�إ� Policy"

    # Step 3: �M���¦� Policy
    Write-Log "Step 3: �M���¦� Policy"
    Get-DnsServerQueryResolutionPolicy | Where-Object { $_.Name -like "NICS-*" } | Remove-DnsServerQueryResolutionPolicy -Force

    # Step 4: Ū���M��B�L�o�P�h��
    Write-Log "Step 4: Ū���M��B�L�o�P�h��"
    $domains = Get-Content $DST | Where-Object { $_ -and ($_ -match "^[a-zA-Z0-9.-]+$") } | Sort-Object -Unique

    # Step 5: �妸�إ� Policy
    Write-Log "Step 5: �妸�إ� Policy"
    $success = 0
    $fail    = 0
    foreach ($line in $domains) {
        try {
            Add-DnsServerQueryResolutionPolicy -Name "NICS-$line" -Action DENY -FQDN "EQ,*.$line" -PassThru -ErrorAction Stop | Out-Null
            $success++
        } catch {
            $fail++
            Write-Log "        �s�W����: $line"
        }
    }

    Write-Log "        ���\�s�W $success ���A���� $fail ��"
}

# Step 6: �Τ@�o�e Email
Write-Log "Step 6: �o�e Email �q��"
$body = if ($needUpdate) {
    "�¦W���s����`n���\�s�W: $success ��`n�s�W����: $fail ��`n�Ӯ�: $((Get-Date) - $start).TotalSeconds ��"
} else {
    "�¦W�楼�ܧ�A�L�ݧ�s Policy"
}

try {
    Send-MailMessage -To $MailTo -From $MailFrom -Subject "[NICS] �¦W���s���A" `
                     -Body $body -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$false -Encoding UTF8
    Write-Log "        �w�o�e Email �q�� $MailTo"
} catch {
    Write-Log "        Email �o�e����: $_"
}

$end = Get-Date
$duration = ($end - $start).TotalSeconds
Write-Log "��������A�`�Ӯ� $duration ��"
Write-Log "========== NICS-Update.ps1 END =========="
