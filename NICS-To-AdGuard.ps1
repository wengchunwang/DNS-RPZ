# ======================================================
# NICS-To-AdGuard.ps1 20250903-005
# �\��:
#  - �ˬd��l�¦W��O�_�s�b ($SRC)�C
#  - ��� SHA256 �T�{�O�_����s�A�L��s�h���L�]���O���Ӯɡ^�C
#  - �ഫ�� AdGuard �a�ή榡�A�۰ʥ[�W header �P�C�� ||...^�C
#  - �۰ʲ����ӷ����� http:// �P https:// �e��C
#  - �έp���� �üg�J log�C
#  - �g�J������ NAS log�]�p�G���w $NASPath�^�C
#  - ��s SHA256 �����ɡC
#  - ���\��۰ʽƻs $DST �� NAS (AdGuard.txt)�C
#  - �o�e Email �q���]�Ȧb����s�ɡ^�C
#  - ��X�����T���P�Ӯɲέp�C
# ======================================================
param (
    [string]$SRC,       # ��l�¦W��
    [string]$DST,       # �ഫ���ɮ�
    [string]$NASPath,   # NAS LOG �P��X�ؿ�
    [string]$MailFrom,
    [string]$MailTo,
    [string]$SMTPServer,
    [int]$SMTPPort
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
    if ($logFileNAS) {
        try {
            Add-Content -Path $logFileNAS -Value "[$timestamp] $env:COMPUTERNAME $Message" -ErrorAction Stop
        } catch {
            Add-Content -Path $logFile -Value "[$timestamp] �L�k�g�J NAS Log: $($_.Exception.Message)"
        }
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

$ErrorActionPreference = "Stop"

Write-Log "========== NICS-To-AdGuard.ps1 20250903-005 =========="

# -----------------------------
# �ˬd��l�ɬO�_�s�b
# -----------------------------
Write-Log "Step 1: �ˬd��l�ɬO�_�s�b"
if (-not (Test-Path $SRC)) {
    Write-Log "        �ӷ��ɤ��s�b: $SRC"
    $end = Get-Date
    $duration = "{0:N2}" -f (($end - $start).TotalSeconds)
    Write-Log "        [INFO] �����A�ӷ����s�b�A�`�Ӯ� $duration ��"
    Write-Log "========== NICS-To-AdGuard.ps1 20250903-005 =========="
    exit
}

# -----------------------------
# �p���l�� SHA256
# -----------------------------
Write-Log "Step 2: �p���l�� SHA256"
$hashFile = "$SRC.sha256"
$sha256   = Get-FileHash -Path $SRC -Algorithm SHA256 | Select-Object -ExpandProperty Hash
$oldHash  = if (Test-Path $hashFile) { Get-Content $hashFile -ErrorAction SilentlyContinue } else { "" }

if ($sha256 -eq $oldHash) {
    Write-Log "        �¦W��L�ܧ�A���L�ഫ"
    $end = Get-Date
    $duration = "{0:N2}" -f (($end - $start).TotalSeconds)
    Write-Log "        [INFO] �����]�L�ܧ�^�A�`�Ӯ� $duration ��"
    Write-Log "========== NICS-To-AdGuard.ps1 20250903-005 =========="
    exit
}

# -----------------------------
# �ഫ AdGuard �榡�òέp����
# -----------------------------
Write-Log "Step 3: �ഫ AdGuard �榡�òέp����"

$lines = Get-Content $SRC | Where-Object { $_.Trim() -ne "" } |
    ForEach-Object { ($_ -replace '^(https?://)', '') }

$recordCount = $lines.Count

$AdGuardHeader = @(
    "! Title: AdGuard.txt"
    "! Last modified: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    "!"
)
$AdGuardBody = $lines | ForEach-Object { "||$_^" }

# �X�� header �P body
$AdGuardContent = $AdGuardHeader + $AdGuardBody
Set-Content -Path $DST -Value $AdGuardContent -Encoding UTF8

Write-Log "        �¦W��w�ഫ�� AdGuard �榡: $DST�A�`����: $recordCount"

# ��s SHA256
Set-Content -Path $hashFile -Value $sha256

# -----------------------------
# �ƻs�� NAS (�p�G���w)
# -----------------------------
if ($NASPath) {
    try {
        $nasFile = Join-Path $NASPath "AdGuard.txt"
        Copy-Item -Path $DST -Destination $nasFile -Force
        Write-Log "        �w�ƻs AdGuard �¦W��� NAS: $nasFile"
    } catch {
        Write-Log "        �ƻs�� NAS ����: $($_.Exception.Message)"
    }
}

# -----------------------------
# �o�e Email �q���]�Ȧb����s�^
# -----------------------------
if ($MailFrom -and $MailTo -and $SMTPServer) {
    $BodyEmail = @"
�¦W��w��s���ഫ�� AdGuard �榡
�ɮצW�١G$DST
�`���ơG$recordCount
�ɶ��G$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
    try {
        Send-MailMessage -From $MailFrom -To $MailTo -Subject "[NICS] �¦W��w��s���ഫ�� AdGuard �榡" `
            -Body $BodyEmail -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$false -Encoding UTF8
        Write-Log "        Email �w�o�e�� $MailTo"
    } catch {
        Write-Log "        Email �o�e����: $($_.Exception.Message)"
    }
}

# -----------------------------
# �����T���P�Ӯ�
# -----------------------------
$end = Get-Date
$duration = "{0:N2}" -f (($end - $start).TotalSeconds)
Write-Log "        [INFO] �����A�ഫ�ɮפw�ͦ�: $DST�A�`�Ӯ� $duration ��A�`���� $recordCount"
Write-Log "========== NICS-To-AdGuard.ps1 20250903-005 =========="

# Write-Host "[INFO] �����A�ഫ�ɮפw�ͦ�: $DST�A�`����: $recordCount"
