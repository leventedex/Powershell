# ----------------------------------------------------------
# System Inventory Script
# ----------------------------------------------------------

Write-Host "Collecting system information..." -ForegroundColor Cyan

# --- FQDN ---
try {
    $FQDN = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
}
catch {
    $FQDN = $env:COMPUTERNAME
}

# --- IP Addresses ---
$IPAddresses = (Get-NetIPAddress -AddressFamily IPv4 `
    | Where-Object { $_.IPAddress -notlike "169.*" -and $_.IPAddress -ne "127.0.0.1" } `
    | Select-Object -ExpandProperty IPAddress) -join ", "

# --- OS Name & Version ---
$OS = Get-WmiObject Win32_OperatingSystem
$OSName = $OS.Caption
$OSVersion = $OS.Version

# --- Storage (FileSystem Drives) ---
$Drives = Get-PSDrive -PSProvider FileSystem |
    Select-Object Name, Root, Used, Free

# --- RAM ---
$RAM_GB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)

# --- CPU Info ---
$CPU = Get-WmiObject Win32_Processor |
    Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors

# --- Build final object ---
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

# --- Output ---
Write-Host ""
Write-Host "===== SYSTEM INFORMATION =====" -ForegroundColor Green
$SystemInfo | Format-List

Write-Host ""
Write-Host "===== FILE SYSTEM DRIVES =====" -ForegroundColor Green
$Drives | Format-Table -AutoSize


# ----------------------------------------------------------
# TXT EXPORT
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

    # Build content for txt
    $txtContent = @()
    $txtContent += "===== SYSTEM INFORMATION ====="
    $txtContent += ""
    $txtContent += "Host FQDN:     $FQDN"
    $txtContent += "IP Address(es): $IPAddresses"
    $txtContent += "OS Name:       $OSName"
    $txtContent += "OS Version:    $OSVersion"
    $txtContent += "RAM (GB):      $RAM_GB"
    $txtContent += "CPU:           $($CPU.Name)"
    $txtContent += "Cores:         $($CPU.NumberOfCores)"
    $txtContent += "Logical CPUs:  $($CPU.NumberOfLogicalProcessors)"
    $txtContent += ""
    $txtContent += "===== FILE SYSTEM DRIVES ====="
    $txtContent += ""

    foreach ($d in $Drives) {
        $txtContent += "Drive $($d.Name): Root=$($d.Root) Used=$([math]::Round($d.Used/1GB,2))GB Free=$([math]::Round($d.Free/1GB,2))GB"
    }

    # Write to TXT
    $txtContent | Out-File -FilePath $filepath -Encoding UTF8

    Write-Host "TXT file successfully created at: $filepath" -ForegroundColor Green
}
else {
    Write-Host "TXT export skipped." -ForegroundColor Yellow
}