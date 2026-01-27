# ----------------------------------------------------------
# System Inventory Script (with SMB Shares + TXT Export)
# Windows Server 2012 R2 compatible
# ----------------------------------------------------------

Write-Host "Collecting system information..." -ForegroundColor Cyan

# --- FQDN ---
try {
    $FQDN = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
}
catch {
    $FQDN = $env:COMPUTERNAME
}

# --- IP Addresses (IPv4) ---
# Prefer Get-NetIPAddress (PS 4+), fallback to WMI for older/edge cases
try {
    $ipList = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.IPAddress -notlike "169.*" -and $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -ExpandProperty IPAddress
}
catch {
    $ipList = (Get-WmiObject Win32_NetworkAdapterConfiguration |
                Where-Object { $_.IPEnabled -eq $true -and $_.IPAddress }) |
              ForEach-Object { $_.IPAddress } |
              Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and $_ -ne "127.0.0.1" }
}
$IPAddresses = ($ipList | Sort-Object -Unique) -join ", "

# --- OS Name & Version (WMI, as requested) ---
$OS = Get-WmiObject Win32_OperatingSystem
$OSName = $OS.Caption
$OSVersion = $OS.Version

# --- Storage (FileSystem Drives) ---
$Drives = Get-PSDrive -PSProvider FileSystem |
    Select-Object Name, Root, Used, Free

# --- RAM (GB) ---
$RAM_GB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)

# --- CPU Info ---
$CPU = Get-WmiObject Win32_Processor |
    Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors

# --- SMB Shares ---
try {
    $SMBShares = Get-SmbShare | Select-Object Name, Path, Description, ScopeName, ShareState
}
catch {
    $SMBShares = "SMB Share information unavailable."
}

# --- Build summary object (for quick view / potential export) ---
$SystemInfo = [PSCustomObject]@{
    HostFQDN   = $FQDN
    IPAddress  = $IPAddresses
    OSName     = $OSName
    OSVersion  = $OSVersion
    RAM_GB     = $RAM_GB
    CPUName    = $CPU.Name
    Cores      = $CPU.NumberOfCores
    LogicalCPU = $CPU.NumberOfLogicalProcessors
}

# --- Console Output ---
Write-Host ""
Write-Host "===== SYSTEM INFORMATION =====" -ForegroundColor Green
$SystemInfo | Format-List

Write-Host ""
Write-Host "===== FILE SYSTEM DRIVES =====" -ForegroundColor Green
$Drives |
    Select-Object Name, Root,
        @{n='Used(GB)';e={[math]::Round($_.Used/1GB,2)}},
        @{n='Free(GB)';e={[math]::Round($_.Free/1GB,2)}} |
    Format-Table -AutoSize

Write-Host ""
Write-Host "===== SMB SHARES =====" -ForegroundColor Green
if ($SMBShares -is [string]) {
    Write-Host $SMBShares -ForegroundColor Yellow
}
else {
    $SMBShares | Format-Table Name, Path, Description, ScopeName, ShareState -AutoSize
}

# ----------------------------------------------------------
# TXT EXPORT (Prompt for path+name; default if empty)
# ----------------------------------------------------------

$exportTXT = Read-Host "Do you want to export the results to a TXT file? (Y/N)"

if ($exportTXT -match '^(Y|y)$') {

    $timestamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $defaultName = "$env:COMPUTERNAME" + "_" + $timestamp + ".txt"
    $defaultPath = "C:\Temp\$defaultName"

    Write-Host "Enter the full path and filename for the TXT export." -ForegroundColor Cyan
    $userPath = Read-Host "Press ENTER to use default:`n$defaultPath"

    if ([string]::IsNullOrWhiteSpace($userPath)) {
        $filepath = $defaultPath
    }
    else {
        $filepath = $userPath
    }

    # Create directory if missing
    $folder = Split-Path $filepath
    if (!(Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    # Build content for TXT
    $txtContent = @()
    $txtContent += "===== SYSTEM INFORMATION ====="
    $txtContent += ""
    $txtContent += "Host FQDN:      $FQDN"
    $txtContent += "IP Address(es): $IPAddresses"
    $txtContent += "OS Name:        $OSName"
    $txtContent += "OS Version:     $OSVersion"
    $txtContent += "RAM (GB):       $RAM_GB"
    $txtContent += "CPU:            $($CPU.Name)"
    $txtContent += "Cores:          $($CPU.NumberOfCores)"
    $txtContent += "Logical CPUs:   $($CPU.NumberOfLogicalProcessors)"
    $txtContent += ""
    $txtContent += "===== FILE SYSTEM DRIVES ====="
    $txtContent += ""

    foreach ($d in $Drives) {
        $usedGB = if ($d.Used -ne $null) { [math]::Round($d.Used/1GB, 2) } else { 0 }
        $freeGB = if ($d.Free -ne $null) { [math]::Round($d.Free/1GB, 2) } else { 0 }
        $txtContent += "Drive $($d.Name): Root=$($d.Root) Used=${usedGB}GB Free=${freeGB}GB"
    }

    $txtContent += ""
    $txtContent += "===== SMB SHARES ====="
    $txtContent += ""

    if ($SMBShares -is [string]) {
        $txtContent += $SMBShares
    }
    else {
        foreach ($s in $SMBShares) {
            $desc = if ([string]::IsNullOrWhiteSpace($s.Description)) { "" } else { $s.Description }
            $txtContent += "Share: $($s.Name) | Path: $($s.Path) | Description: $desc | Scope: $($s.ScopeName) | State: $($s.ShareState)"
        }
    }

    # Write to TXT
    $txtContent | Out-File -FilePath $filepath -Encoding UTF8

    Write-Host "TXT file successfully created at: $filepath" -ForegroundColor Green
}
else {
    Write-Host "TXT export skipped." -ForegroundColor Yellow
}
