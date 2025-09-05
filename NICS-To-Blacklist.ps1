# ======================================================
# NICS-To-Blacklist.ps1
# �\��:
#  - �ˬd��l�¦W��O�_�s�b ($SRC)�C
#  - ��� SHA256 �T�{�O�_����s�A�L��s�h���L�]�������Ӯɡ^�C
#  - �ഫ�����w�榡 (AdGuard / Pi-hole / All)�C
#  - �έp���ƨüg�J LOG�C
#  - �۰ʲM�z LOG�G
#       - ���� log �O�d 3 ��
#       - NAS log �O�d 30 ��
#  - �o�e Email �q���]�i��^�C
#  - �ƻs�ഫ�ɦ� NAS�]�i��^�C
# ======================================================

param (
    [string]$SRC,       # ��l�¦W��
    [string]$DST,       # �ഫ���ɮװ򩳦W�� (���t���ɦW)
    [string]$NASPath,   # NAS LOG �ؿ�
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
$logDir = Split-Path $logFile
# ���� log �O�d 3 ��
Get-ChildItem -Path $logDir -Filter "NICS-Policy-*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
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

# -----------------------------
# �D�y�{
# -----------------------------
Write-Log "========== NICS-To-Blacklist.ps1 $version =========="

# �ˬd��l��
Write-Log "Step 1: �ˬd��l�ɬO�_�s�b"
if (-not (Test-Path $SRC)) {
    Write-Log "        �ӷ��ɤ��s�b: $SRC"
    $duration = (New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
    Write-Log "        [INFO] �����A�Ӯ� $duration ��"
    Write-Log "========== NICS-To-Blacklist.ps1 END =========="
    exit
}

# -----------------------------
# Ū���P�M�z���e
# -----------------------------
$rawContent = [IO.File]::ReadAllText($SRC)
$rawContent = ($rawContent -split "`r?`n" | Where-Object { $_.Trim() -ne "" }) -join "`n"

if (-not $rawContent) {
    Write-Log "�ӷ��ɬ��šA����B�z"
    Write-Log "========== NICS-To-Blacklist.ps1 END =========="
    exit
}

# -----------------------------
# �p�� SHA256
# -----------------------------
Write-Log "Step 2: �p���l�� SHA256"

$sha256 = Get-FileHash -InputStream ([System.IO.MemoryStream]::new(
    [System.Text.Encoding]::UTF8.GetBytes($rawContent)
)) -Algorithm SHA256 | Select-Object -ExpandProperty Hash

# �쥻�g�k
#$hashFile   = "$SRC.$Format.sha256"
# �s�g�k�G�Τ@²�Ʈ榡�W��
$hashFile   = Join-Path (Split-Path $SRC) "$Format.sha256"

$oldHash    = if (Test-Path $hashFile) { Get-Content $hashFile -ErrorAction SilentlyContinue } else { "" }

# �Y�ӷ��S�ܧ� + �ഫ�ɤw�s�b�A�h���L
if ($sha256 -eq $oldHash) {
    Write-Log "        �¦W��L�ܧ�A���L�ഫ"
    $duration = (New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
    Write-Log "        [INFO] �����]�L�ܧ�^�A�Ӯ� $duration ��"
    Write-Log "========== NICS-To-Blacklist.ps1 END =========="
    exit
}

# -----------------------------
# �ഫ�榡
# -----------------------------
Write-Log "Step 3: �ഫ�� $Format �榡"

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
    Write-Log "        �¦W��w�ഫ�� $fmt �榡: $outFile�A�`����: $recordCount"
}

# ��s SHA256
Set-Content -Path $hashFile -Value $sha256

# -----------------------------
# �o�e Email�]�i��^
# -----------------------------
if ($MailFrom -and $MailTo -and $SMTPServer) {
    $subjectFmt = ($targets -join ", ")
    $subject    = "[NICS] �¦W��w��s ($subjectFmt)"

    $outFiles = foreach ($fmt in $targets) { Get-OutputPath -basePath $DST -fmt $fmt }

    $BodyEmail = @"
�¦W��w��s���ഫ�� $subjectFmt �榡
��X�ɮסG
$outFiles

�`���ơG$recordCount
�ɶ��G$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

    try {
        Send-MailMessage -From $MailFrom -To $MailTo -Subject $subject `
            -Body $BodyEmail -SmtpServer $SMTPServer -Port $SMTPPort -UseSsl:$UseSsl -Encoding UTF8
        Write-Log "        Email �w�o�e�� $MailTo"
    } catch {
        Write-Log "        Email �o�e����: $($_.Exception.Message)"
    }
}

$end = Get-Date
$duration = ($end - $start).TotalSeconds
Write-Log "        [INFO] �����A�`�Ӯ� $duration ��A�`���� $recordCount"
Write-Log "========== NICS-To-Blacklist.ps1 END =========="
